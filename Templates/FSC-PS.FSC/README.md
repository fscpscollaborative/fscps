# FSC-PS. D365FSC Development Userguide 


1. Generate GitHub PAT(Personal Access Token)

- Login to your GitHub account and open Settings 
![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_a.png)

- Developer Settings 
![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_b.png)

- Personal Access Token -> Generate New Token 
 ![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_c.png)

 ![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_d.png)

- Copy and save your PAT somewhere and click the Authorize SSO 
![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_e.png)

2. Map the repository code
- Log in to your devbox and run the Powershell ISE with administrator permissions.
- Change the variables values and execute the folowing powershell code.

~~~javascript
$GitGlobalUserName  = "Oleksandr Nikolaiev"
$GitGlobalEmail     = "Oleksandr.Nikolaiev@contosoinc.com"
$GitFnORepoURL      = "https://github.com/ContosoInc/ContesoExt-dynamics-365-FO.git"
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

#Update Git EnvPath variable
$GitPath = [System.String]";C:\Program Files\Git\bin\;C:\Program Files\Git\cmd\";
if(-Not ([System.String]$env:Path -like "*" + $GitPath + "*"))
{
    $env:Path += $GitPath;
}

$LocalFnODeploymentFolder = Get-FnODeploymentFolder
cd $LocalFnODeploymentFolder
if( -Not (Test-Path  ".git"))
{
    git clone -b main $GitFnORepoURL tmp
    mv tmp/.git $LocalFnODeploymentFolder
    rmdir tmp -Recurse
    git config --global user.name $GitGlobalUserName
    git config --global user.email $GitGlobalEmail
    git reset --hard HEAD
    git fetch 
    git pull
}

~~~

Paste the generated PAT into the popup GitHub window.

3. Configure VisualStudio
- Open VisualStudio and select “Open a Local Folder”

![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_f.png)

- Find the AOSService folder and click select 

![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_g.png)

- Go to Tools->Options 

![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_h.png)

- Set Projects locations to AOSService/VSSProjects folder and click OK button. 

![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_i.png)
