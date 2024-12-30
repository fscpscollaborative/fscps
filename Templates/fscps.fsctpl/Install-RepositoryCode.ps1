[CmdletBinding()]
param (
    [Parameter()]
    [String]
    $GitGlobalUserName,

    [Parameter()]
    [String]
    $GitGlobalEmail,

    [Parameter()]
    [String]
    $GitFnORepoURL
)

#region Git setup
# TODO: Add a check to see if git is installed and install it if it is not

## Update Git EnvPath variable
$GitPath = [System.String]";C:\Program Files\Git\bin\;C:\Program Files\Git\cmd\";
if (-not ([System.Environment]::GetEnvironmentVariable("Path", "User") -like "*$GitPath*"))
{
    $newPath = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";$GitPath"
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Output "Added Git to the PATH environment variable. Please restart the shell to use the new PATH."
    Exit
}

if (-not (git --version))
{
    Write-Output "Git is not installed. Please install Git and run this script again."
    Exit
}

## Configure git
if (-not $GitGlobalUserName)
{
    $GitGlobalUserName = git config --global user.name
}
if (-not $GitGlobalUserName)
{
    $GitGlobalUserName = Read-Host "Enter the Git global user name (e.g. John Doe)"
}

if (-not $GitGlobalEmail)
{
    $GitGlobalEmail = git config --global user.email
}
if (-not $GitGlobalEmail)
{
    $GitGlobalEmail = Read-Host "Enter the Git global user email (e.g. john.doe@company.com)"
}

if ($GitGlobalUserName -and $GitGlobalEmail)
{
    git config --global user.name $GitGlobalUserName
    git config --global user.email $GitGlobalEmail
}
#endregion

#region Map FnO repository
if (-not $GitFnORepoURL)
{
    $GitFnORepoURL = Read-Host "Enter the URL of the FnO repository (e.g. https://github.com/user/repo.git)"
}
if (-not $GitFnORepoURL)
{
    Write-Output "No repository URL provided. Exiting."
    Exit
}

#
# Retrieve the FnO deployment location 
#
function Get-FnODeploymentFolder
{
    if (Test-Path -Path K:\AosService)
    {
       return "K:\AosService"
    }
    elseif (Test-Path -Path C:\AosService)
    {
       return "C:\AosService"
    }
    elseif (Test-Path -Path J:\AosService)
    {
       return "J:\AosService"
    }
    elseif (Test-Path -Path I:\AosService)
    {
       return "I:\AosService"
    }
    else
    {
      throw "Cannot find the AOSService folder in any known location"
    }
}

$LocalFnODeploymentFolder = Get-FnODeploymentFolder
Set-Location $LocalFnODeploymentFolder
if( -Not (Test-Path  ".git"))
{
    git clone -b main $GitFnORepoURL tmp
    Move-Item tmp/.git $LocalFnODeploymentFolder
    Remove-Item tmp -Recurse
    git reset --hard HEAD
    git fetch 
    git pull
}

#endregion