# GithubNewsBot.ps1
# Requires PowerShell 5.1+

# --- 1. CONFIGURATION ---
# Read from environment variables (provided by GitHub Actions)
$TELEGRAM_BOT_TOKEN = $env:TELEGRAM_BOT_TOKEN
$TELEGRAM_CHAT_ID = $env:TELEGRAM_CHAT_ID
$GEMINI_API_KEY = $env:GEMINI_API_KEY

if (-not $TELEGRAM_BOT_TOKEN -or -not $TELEGRAM_CHAT_ID) {
    Write-Host "[ERROR] Thieu thong tin Telegram trong Environment"
    exit 1
}

if (-not $GEMINI_API_KEY) {
    Write-Host "[WARNING] Khong co GEMINI_API_KEY. Se chay che do khong AI."
}

# --- 2. HELPER FUNCTIONS ---
function Get-Date7DaysAgo {
    return (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
}

function Search-GithubRepos {
    param([string]$Query)
    $Url = "https://api.github.com/search/repositories?q=$Query&sort=stars&order=desc&per_page=5"
    $Headers = @{
        "Accept" = "application/vnd.github.v3+json"
        "User-Agent" = "GithubNewsBot"
    }
    
    try {
        $Response = Invoke-RestMethod -Uri $Url -Method Get -Headers $Headers
        return $Response.items
    } catch {
        Write-Host "[ERROR] Loi khi goi Github API: $_"
        return @()
    }
}

function Get-GithubReadme {
    param([string]$FullName)
    $Url = "https://api.github.com/repos/$FullName/readme"
    $Headers = @{
        "Accept" = "application/vnd.github.v3.raw"
        "User-Agent" = "GithubNewsBot"
    }
    
    try {
        $Readme = Invoke-RestMethod -Uri $Url -Method Get -Headers $Headers
        if ($Readme.Length -gt 5000) {
            return $Readme.Substring(0, 5000)
        }
        return $Readme
    } catch {
        return "No README available."
    }
}

function Summarize-WithGemini {
    param([string]$RepoName, [string]$Description, [string]$ReadmeContent)
    
    if (-not $GEMINI_API_KEY) {
        return "<p><i>Mo ta goc:</i> $($Description -replace '<','&lt;' -replace '>','&gt;')</p>"
    }

    $Url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent"
    
    $Prompt = "You are a tech reporter. Briefly summarize this GitHub repository in Vietnamese. Focus on: 1) What it does. 2) How to use/install it. Format the output strictly in basic HTML tags like <p>, <b>, <ul>, <li>. Do NOT use markdown. Repo: $RepoName. Desc: $Description. README: $ReadmeContent"
    
    $Body = @{
        contents = @(
            @{ parts = @( @{ text = $Prompt } ) }
        )
    } | ConvertTo-Json -Depth 5 -Compress

    $Headers = @{
        "Content-Type" = "application/json"
        "X-goog-api-key" = $GEMINI_API_KEY
    }

    try {
        $Response = Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Body
        $Summary = $Response.candidates[0].content.parts[0].text
        # Remove any markdown code block wrappers if Gemini accidentally includes them
        $Summary = $Summary -replace "^```html`n", "" -replace "`n```$", ""
        return $Summary.Trim()
    } catch {
        Write-Host "[ERROR] Loi khi goi Gemini API: $_"
        return "<p><i>Loi khi tom tat:</i> $($Description -replace '<','&lt;' -replace '>','&gt;')</p>"
    }
}

function Send-TelegramMessage {
    param([string]$Message)
    
    $Url = "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
    $Body = @{
        chat_id = $TELEGRAM_CHAT_ID
        text = $Message
        parse_mode = "HTML"
        disable_web_page_preview = $true
    } | ConvertTo-Json -Depth 3 -Compress

    $Headers = @{
        "Content-Type" = "application/json"
    }

    try {
        Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -Body $Body | Out-Null
        Write-Host "[SUCCESS] Da gui tin nhan qua Telegram."
    } catch {
        Write-Host "[ERROR] Loi khi gui Telegram: $_"
    }
}

# --- 3. MAIN LOGIC & HTML GENERATION ---
Write-Host "[INFO] Bat dau quet Github Trending..."
$DateString = Get-Date7DaysAgo

$NewRepos = Search-GithubRepos -Query "created:>=$DateString"
$ActiveRepos = Search-GithubRepos -Query "pushed:>=$DateString"

$CurrentDate = (Get-Date).ToString("dd/MM/yyyy")

$HtmlStart = @"
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bản tin Github Trending - $CurrentDate</title>
    <style>
        :root {
            --bg: #0d1117;
            --card-bg: #161b22;
            --border: #30363d;
            --text: #c9d1d9;
            --title: #58a6ff;
            --accent: #238636;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg);
            color: var(--text);
            margin: 0;
            padding: 20px;
            line-height: 1.6;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
        }
        h1, h2 {
            color: var(--text);
            border-bottom: 1px solid var(--border);
            padding-bottom: 10px;
        }
        .repo-card {
            background-color: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 6px;
            margin-bottom: 15px;
            overflow: hidden;
        }
        summary {
            padding: 15px;
            cursor: pointer;
            font-size: 1.1em;
            font-weight: 600;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        summary:hover {
            background-color: #1f242c;
        }
        .repo-name {
            color: var(--title);
            text-decoration: none;
        }
        .repo-name:hover {
            text-decoration: underline;
        }
        .stars {
            font-size: 0.9em;
            color: #8b949e;
            background: #21262d;
            padding: 2px 8px;
            border-radius: 12px;
            border: 1px solid var(--border);
        }
        .details-content {
            padding: 15px;
            border-top: 1px solid var(--border);
            background-color: #0d1117;
        }
        .badge {
            display: inline-block;
            background-color: var(--accent);
            color: #fff;
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.8em;
            margin-bottom: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Github Trending - $CurrentDate</h1>
        <p>Bản tin tổng hợp các công cụ và dự án mã nguồn mở đáng chú ý nhất tuần qua.</p>
        
        <h2>🔥 Top Dự Án Mới Nhất</h2>
"@

$HtmlContent = ""

if ($NewRepos) {
    foreach ($repo in $NewRepos) {
        $Name = $repo.full_name
        $Url = $repo.html_url
        $Stars = $repo.stargazers_count
        
        Write-Host "[INFO] Xu ly repo moi: $Name"
        $Readme = Get-GithubReadme -FullName $Name
        $SummaryHtml = Summarize-WithGemini -RepoName $Name -Description $repo.description -ReadmeContent $Readme

        $HtmlContent += @"
        <details class="repo-card">
            <summary>
                <span><a href="$Url" class="repo-name" target="_blank">$Name</a></span>
                <span class="stars">⭐ $Stars</span>
            </summary>
            <div class="details-content">
                <span class="badge">Mới nổi</span>
                $SummaryHtml
            </div>
        </details>
"@
    }
}

$HtmlContent += "<h2>📈 Top Dự Án Sôi Nổi Nhất</h2>"

if ($ActiveRepos) {
    foreach ($repo in $ActiveRepos) {
        $Name = $repo.full_name
        $Url = $repo.html_url
        $Stars = $repo.stargazers_count
        
        Write-Host "[INFO] Xu ly repo hoat dong: $Name"
        $Readme = Get-GithubReadme -FullName $Name
        $SummaryHtml = Summarize-WithGemini -RepoName $Name -Description $repo.description -ReadmeContent $Readme

        $HtmlContent += @"
        <details class="repo-card">
            <summary>
                <span><a href="$Url" class="repo-name" target="_blank">$Name</a></span>
                <span class="stars">⭐ $Stars</span>
            </summary>
            <div class="details-content">
                <span class="badge">Đang Hot</span>
                $SummaryHtml
            </div>
        </details>
"@
    }
}

$HtmlEnd = @"
        <p style="text-align: center; color: #8b949e; margin-top: 40px; font-size: 0.9em;">
            Tạo tự động bởi Github Actions & Gemini AI.
        </p>
    </div>
</body>
</html>
"@

# Combine and save
$FullHtml = $HtmlStart + $HtmlContent + $HtmlEnd
$FullHtml | Out-File -FilePath "index.html" -Encoding UTF8

Write-Host "[INFO] Da tao trang index.html"

# Send Telegram notification
$RepoUrl = "https://vananwebdev.github.io/trend_Repo_Github/"
$TeleMsg = "🚀 <b>Ban tin Github Trending $CurrentDate da san sang!</b>`n`n👉 Doc ngay tai: $RepoUrl"

Write-Host "[INFO] Dang gui ket qua ve Telegram..."
Send-TelegramMessage -Message $TeleMsg
Write-Host "[INFO] Hoan thanh."
