# **Contribute**
If you want to contribute, please, create an issue or  PR on the main project https://github.com/fscpscollaborative/fscps

# D365 ECommerce Development user guide 


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
$GitGlobalUserName          = "Oleksandr Nikolaiev"
$GitGlobalEmail             = "Oleksandr.Nikolaiev@contosoinc.com"
$GitECommerceRepoURL        = "https://github.com/ContosoInc/ContesoExt-dynamics-365-Ecommerce.git"
$microsofteCommerceRepoUrl  = "https://github.com/microsoft/Msdyn365.Commerce.Online.git"
$tempPath                   = "C:\temp"
$fscmVersion                = "10.0.35"
$ecommerceFolder            = "ConteComm"
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

#map eCommerce
Set-Location $LocalCommerceDeploymentFolder 
if( -Not (Test-Path  "$ecommerceFolder\.git")) 
{ 
    ### install python
    Set-Location $tempPath
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.7.0/python-3.7.0.exe" -OutFile "$tempPath\python-3.7.0.exe"
    .\python-3.7.0.exe /quiet InstallAllUsers=0 PrependPath=1 Include_test=0

    ###install yarn 
    npm install --global yarn

    ### clone msdyn365 repo
    Set-Location $tempPath
    Remove-Item $tempPath\Msdyn365.Commerce.Online\* -Recurse -Force -ErrorAction SilentlyContinue
    git clone --quiet $microsofteCommerceRepoUrl
    Set-Location $tempPath\Msdyn365.Commerce.Online\
    git fetch --all
    git checkout RS/$fscmVersion --quiet

    ##copy to the destination
    Set-Location $LocalCommerceDeploymentFolder
    if(!(Test-Path $ecommerceFolder))
    {
        New-Item -ItemType Directory -Path $ecommerceFolder -Force
    }
    Remove-Item $tempPath\Msdyn365.Commerce.Online\.git -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item $tempPath\Msdyn365.Commerce.Online\* -Destination $ecommerceFolder -Recurse -Force

    
    Set-Location $LocalCommerceDeploymentFolder\$ecommerceFolder
    git clone -b main $GitECommerceRepoURL tmp --quiet 
    mv tmp/.git $LocalCommerceDeploymentFolder\$ecommerceFolder 
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
