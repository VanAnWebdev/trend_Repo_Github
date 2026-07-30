# GithubNewsBot.ps1
# Requires PowerShell 5.1+

$EnvPath = Join-Path $PSScriptRoot ".env"

if (-not (Test-Path $EnvPath)) {
    Write-Host "[ERROR] Khong tim thay file .env tai $EnvPath"
    exit 1
}

$EnvVars = @{}
Get-Content $EnvPath -Encoding UTF8 | Where-Object { $_ -match '=' -and $_ -notmatch '^#' } | ForEach-Object {
    $parts = $_ -split '=', 2
    $EnvVars[$parts[0].Trim()] = $parts[1].Trim()
}

$TELEGRAM_BOT_TOKEN = $EnvVars["TELEGRAM_BOT_TOKEN"]
$TELEGRAM_CHAT_ID = $EnvVars["TELEGRAM_CHAT_ID"]
$GEMINI_API_KEY = $EnvVars["GEMINI_API_KEY"]

if (-not $TELEGRAM_BOT_TOKEN -or -not $TELEGRAM_CHAT_ID) {
    Write-Host "[ERROR] Thieu thong tin Telegram trong Environment"
    exit 1
}

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
        return "<p><i>Description:</i> $($Description -replace '<','&lt;' -replace '>','&gt;')</p>"
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
        $Summary = $Summary -replace "^```html`n", "" -replace "`n```$", ""
        return $Summary.Trim()
    } catch {
        return "<p><i>Error summarizing:</i> $($Description -replace '<','&lt;' -replace '>','&gt;')</p>"
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
    } catch {
    }
}

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
    <title>Ban tin Github Trending - $CurrentDate</title>
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
        <h1>Github Trending - $CurrentDate</h1>
        <p>Ban tin tong hop cac cong cu va du an dang chu y.</p>
        
        <h2>Top Du An Moi Nhat</h2>
"@

$HtmlContent = ""

if ($NewRepos) {
    foreach ($repo in $NewRepos) {
        $Name = $repo.full_name
        $Url = $repo.html_url
        $Stars = $repo.stargazers_count
        
        $Readme = Get-GithubReadme -FullName $Name
        $SummaryHtml = Summarize-WithGemini -RepoName $Name -Description $repo.description -ReadmeContent $Readme

        $HtmlContent += @"
        <details class="repo-card">
            <summary>
                <span><a href="$Url" class="repo-name" target="_blank">$Name</a></span>
                <span class="stars">$Stars sao</span>
            </summary>
            <div class="details-content">
                <span class="badge">Moi noi</span>
                $SummaryHtml
            </div>
        </details>
"@
    }
}

$HtmlContent += "<h2>Top Du An Soi Noi Nhat</h2>"

if ($ActiveRepos) {
    foreach ($repo in $ActiveRepos) {
        $Name = $repo.full_name
        $Url = $repo.html_url
        $Stars = $repo.stargazers_count
        
        $Readme = Get-GithubReadme -FullName $Name
        $SummaryHtml = Summarize-WithGemini -RepoName $Name -Description $repo.description -ReadmeContent $Readme

        $HtmlContent += @"
        <details class="repo-card">
            <summary>
                <span><a href="$Url" class="repo-name" target="_blank">$Name</a></span>
                <span class="stars">$Stars sao</span>
            </summary>
            <div class="details-content">
                <span class="badge">Dang Hot</span>
                $SummaryHtml
            </div>
        </details>
"@
    }
}

$HtmlEnd = @"
        <p style="text-align: center; color: #8b949e; margin-top: 40px; font-size: 0.9em;">
            Tao boi Github Actions.
        </p>
    </div>
</body>
</html>
"@

$FullHtml = $HtmlStart + $HtmlContent + $HtmlEnd
$FullHtml | Out-File -FilePath "index.html" -Encoding UTF8

$RepoUrl = "https://vananwebdev.github.io/trend_Repo_Github/"
$TeleMsg = "<b>Ban tin Github Trending $CurrentDate da san sang!</b>`n`nDoc ngay tai: $RepoUrl"

Send-TelegramMessage -Message $TeleMsg
