# Settings
The behavior of FSC-PS for GitHub is very much controlled by the settings in the settings file.

## Where is the settings file located
An FSC-PS repository can consist of a single project (with multiple apps) or multiple projects (each with multiple apps). Multiple projects in a single repository are comparable to multiple repositories; they are built, deployed, and tested separately. All apps in each project (single or multiple) are built together in the same pipeline, published and tested together. If a repository is multiple projects, each project is stored in a separate folder in the root of the repository.

When running a workflow or a local script, the settings are applied by reading one or more settings files. Last applied settings file wins. The following lists the settings files and their location:

**.github\\FSC-PS-settings.json** is the repository settings file. This settings file contains settings that are relevant for all projects in the repository. If a settings in the repository settings file is found in a subsequent settings file, it will be overridden by the new value.

**.FSC-PS\\settings.json** is the project settings file. If the repository is a single project, the .FSC-PS folder is in the root folder of the repository. If the repository contains multiple projects, there will be a .FSC-PS folder in each project folder.

**.FSC-PS\\\<workflow\>.settings.json** is the workflow-specific settings file. This option is used for the Current, NextMinor and NextMajor workflows to determine artifacts and build numbers when running these workflows.

**.FSC-PS\\\<username\>.settings.json** is the user-specific settings file. This option is rarely used, but if you have special settings, which should only be used for one specific user (potentially in the local scripts), these settings can be added to a settings file with the name of the user followed by `.settings.json`.

## Basic settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| type | Specifies the type of project. Allowed values are **FSCM** or **Retail**. This value comes with the default repository. | FSCM |
| companyName | Company name using for generate the package name.  | |
| buildVersion | The default D365 FSC version used to build and generate the package. Can be overriden by FSC-PS-Settings/environment/build/ci/deploy settings  | |
| models | The models string array taking a part in the solution. Should be specified with comma delimeter. Example ("Contoso,ContosoTextExtension,ContosoExtension")| |
| buildPath | The FSC-PS system will copy the {github.workspace} into this folder and will do the build from it. The folder will be located inside C:\Temp\   | _bld |
| metadataPath | FSC specific. Specify the folder hat contains the FSC models  {github.workspace}\{metadataPath} | PackagesLocalDirectory |
| modelsIntoPackagePattern | FSC specific. Search pattern for binaries to package. Optional search pattern for the packages to include from the binaries location. Wildcards can be used, or a list of packages by specifying one package name per line. | * |
| deployScheduleCron | CRON schedule for when deploy workflow should run. Default is execute each first minute of hour, only manual trigger. Build your CRON string here: https://crontab.guru | 1 * * * * |
| generatePackages | Option to generate a package after build. Often used in build, deploy and release workflows | true |
| uploadPackageToLCS | Option to upload generated package to the LCS after build and generate process. IMPORTANT!!! generatePackages option should be set to True  | false |
| exportModel | FSC specific. Option to generate axmodel file. If more than one models was specified in the "models" parameter, it will take first one, and generate the axmodel file. IMPORTANT!!! generatePackages option should be set to True  | false |

### NuGet settings
The custom NuGet repository settings contains the D365 FSC nuget packages for build. The packages can be downloaded from the LCS Shared Asset Library

| Name | Description | Default value |
| :-- | :-- | :-- |
| nugetFeedName | The name of the Nuget feed.  | |
| nugetSourcePath | The URL of the Nuget feed.  | |
| nugetFeedUserName | The username credential of the NuGet feed. | |
| nugetFeedUserSecretName | The github secret name contains the username credential of the NuGet feed. If specified will be used instead of nugetFeedUserName parameter | |
| nugetFeedPasswordSecretName | The github secret name contains the password credential of the NuGet feed. | |
| nugetPackagesPath | The name of the directory where Nuget packages will be stored  | NuGet |

### LCS settings
These LCS settings should contain the tenant configuration what will use by default for all deployments. Can be overrided in the .FSC-PS\environments.jsom settings.
| Name | Description |
| :-- | :-- | 
| lcsEnvironmentId | The Guid of the LCS environment |
| lcsProjectId | The ID of the LCS project |
| lcsClientId | The ClientId of the azure application what has access to the LCS |
| lcsUsernameSecretname | The github secret name that contains the username what has at least Owner access to the LCS project. It is a highly recommend to create a separate AAD user for this purposes. E.g. lcsadmin@contoso.com |
| lcsPasswordSecretname | The github secret name that contains the password of the LCS user. |

### Azure settings
These Azure settings should contain the tenant configuration what will use by default for all deployments. Used for checking the VM status in the deploy workflow. AAD Application should have "DevTest labs" permitions for the Azure sebscription. Can be overrided in the environments settings.
| Name | Description | 
| :-- | :-- | 
| azTenantId | The Guid of the Azure tenant  | 
| azClientId | The Guid of the AAD registered application  | 
| azClientsecretSecretname | The github secret name that contains ClientSecret of the registered application  | 
| azVmname | The name of the Azure Virtual Machine. Should be specified in the .FSC-PS\environments.json settings  | 
| azVmrg |  The name of the Azure Resouce Group contains the Virtual machine. Should be specified in the .FSC-PS\environments.json settings | 

### Retail settings
These Retail settings should contain the RetailSDK settings. Can be overrided in the .FSC-PS\versions.json settings.
| Name | Description | Default value |
| :-- | :-- | :-- | 
| retailSDKVersion | Retail specific. The RetailSDK version what will use to build the Retail extention. By default the settings from the versions.default.json will be used but can be overriden in .FSC-PS\versions.json file.  | |
| retailSDKZipPath | Retail specific. The path to the directory where RetailSDK archives will be stored  | C:\RSDK |
| retailSDKBuildPath | Retail specific. The path to the directory where RetailSDK will build the extension.  | C:\Temp\RetailSDK |
| retailSDKURL | Retail specific. The direct http link to do download the RetailSDK 7z archive. By default the settings from the versions.default.json will be used but can be overriden in .FSC-PS\versions.json file.  | |

## Runtime generated settings
| Name | Description | Default value |
| :-- | :-- | :-- |
| currentBranch | The workflow execution branch name | {current execution branch} |
| sourceBranch | The branch used to build and generate the package. Using for deployment | {branch name from .FSC-PS\environments.json settings} |

## Basic Repository settings
The repository settings are only read from the repository settings file (.github\FSC-PS-Settings.json)

| Name | Description | Default value |
| :-- | :-- | :-- |
| templateUrl | Defines the URL of the template repository used to create this project and is used for checking and downloading updates to FSC-PS System files. | https://github.com/ciellosinc/FSC-PS-Template |
| templateBranch | Defines the branchranch of the template repository used to create this project and is used for checking and downloading updates to FSC-PS System files. | main |
| runs-on | Specifies which github runner will be used for all jobs in all workflows (except the Update FSC-PS System Files workflow). The default is to use the GitHub hosted runner Windows-latest. You can specify a special GitHub Runner for the build job using the GitHubRunner setting. Read [this](SelfHostedGitHubRunner.md) for more information. | windows-latest |
| githubRunner | Specifies which github runner will be used for the build/ci/deploy/release job in workflows. This is the most time consuming task. By default this job uses the Windows-latest github runner (unless overridden by the runs-on setting). This settings takes precedence over runs-on so that you can use different runners for the build job and the housekeeping jobs. See runs-on setting. | windows-latest |

## Advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| versioningStrategy | The versioning strategy determines how versioning is performed in this project. The version number of an app consists of 4 tuples: **Major**.**Minor**.**Build**.**Revision**. **Major** and **Minor** are read from the app.json file for each app. **Build** and **Revision** are calculated. Currently 3 versioning strategies are supported:<br />**0** = **Build** is the **github [run_number](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** for the CI/CD workflow, increased by the **runNumberOffset** setting value (if specified). **Revision** is the **github [run_attempt](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** subtracted 1.<br />**1** = **Build** is the **github [run_id](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** for the repository. **Revision** is the **github [run_attempt](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** subtracted 1.<br />**2** = **Build** is the current date  as **yyyyMMdd**. **Revision** is the current time as **hhmmss**. Date and time are always **UTC** timezone to avoid problems during daylight savings time change. Note that if two CI/CD workflows are started within the same second, this could yield to identical version numbers from two different runs.<br />**+16** use **repoVersion** setting as **appVersion** (**Major** and **Minor**) for all apps | 0 |
| repoTokenSecretName | Specifies the name (**NOT the secret**) of the REPO_TOKEN secret. Default is REPO_TOKEN. FSC-PS for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as Personal Access Token with permission to modify workflows when running the Update FSC-PS System Files workflow. Read [this](UpdateAlGoSystemFiles.md) for more information. | REPO_TOKEN |
| failOn | Specifies what the pipeline will fail on. Allowed values are none, warning and error | error |
| codeSignCertificateUrlSecretName<br />codeSignCertificatePasswordSecretName | Specifying the secure URL from which your codesigning certificate pfx file can be downloaded and the password for this certificate. These settings specifies the names (**NOT the secrets**) of the code signing certificate url and password. Default is to look for secrets called CodeSignCertificateUrl and CodeSignCertificatePassword. Read [this](SetupCiCdForExistingAppSourceApp.md) for more information. | CodeSignCertificateUrl<br />CodeSignCertificatePassword |


