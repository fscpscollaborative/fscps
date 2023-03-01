# FSC-PS. D365Commerce Development Userguide 


### Generate GitHub PAT(Personal Access Token)

- Login to your GitHub account and open Settings 
![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_a.png)

- Developer Settings 
![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_b.png)

- Personal Access Token -> Generate New Token 
 ![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_c.png)

 ![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_d.png)

- Copy and save your PAT somewhere and click the Authorize SSO 
![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_e.png)

### Map the repository code
- Log in to your devbox and run the Powershell ISE with administrator permissions.
- Change the variables values and execute the folowing powershell code.

~~~javascript
$GitGlobalUserName  = "Oleksandr Nikolaiev"
$GitGlobalEmail     = "Oleksandr.Nikolaiev@contosoinc.com"
$GitFnORepoURL      = "https://github.com/ContosoInc/ContesoExt-dynamics-365-FO.git"
$RetailExtensionFolderName = "ContosoRetailSDK"
#
# Retrieve the Commerce deployment location 
#
function Get-CommerceDeploymentFolder
{
    if (Test-Path -Path K:\RetailSDK)
    {
       return "K:\"
    }
    elseif (Test-Path -Path C:\RetailSDK)
    {
       return "C:\"
    }
    elseif (Test-Path -Path J:\RetailSDK)
    {
       return "J:\"
    }
    elseif (Test-Path -Path I:\RetailSDK)
    {
       return "I:\"
    }
    else
    {
      throw "Cannot find the RetailSDK folder in any known location"
    }
}


#Update Git EnvPath variable
$GitPath = [System.String]";C:\Program Files\Git\bin\;C:\Program Files\Git\cmd\";
if(-Not ([System.String]$env:Path -like "*" + $GitPath + "*"))
{
    $env:Path += $GitPath;
}

$LocalCommerceDeploymentFolder = Get-CommerceDeploymentFolder
cd $LocalCommerceDeploymentFolder

if( -Not (Test-Path  "$RetailExtensionFolderName\.git"))
{
    New-Item -ItemType Directory -Force -Path $RetailExtensionFolderName
    cd $RetailExtensionFolderName
    Copy-Item -Path $LocalCommerceDeploymentFolder\RetailSDK\* -Destination $LocalCommerceDeploymentFolder\$RetailExtensionFolderName -recurse -Force
    git clone -b main $GitCommerceRepoURL tmp
    mv tmp/.git $LocalCommerceDeploymentFolder\$RetailExtensionFolderName
    rmdir tmp -Recurse
    git config --global user.name $GitGlobalUserName
    git config --global user.email $GitGlobalEmail
    git reset --hard HEAD
    git fetch 
    git pull
}


~~~

Paste the generated PAT into the popup GitHub window.

### Configure VisualStudio
- Open VisualStudio and select “Open a Local Folder”

![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_f.png)

- Find the "$RetailExtensionFolderName" folder and click select 

![](https://raw.githubusercontent.com/ciellosinc/FSC-PS/main/Scenarios/images/fsc_dev_g.png)