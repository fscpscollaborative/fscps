# Settings
The behavior of FSC-PS for GitHub is very much controlled by the settings in the settings file.

## Where is the settings file located
When running a workflow or a local script, the settings are applied by reading one or more settings files. Last applied settings file wins. The following lists the settings files and their location:

**.FSC-PS\\settings.json** is the root repository settings file. The .FSC-PS folder should be in the root folder of the repository.

**.github\\FSC-PS-settings.json** is the repository settings file. This settings file contains settings for the repository. If a settings in the repository settings file is found in a subsequent settings file, it will be overridden by the new value.

**.FSC-PS\\\<workflow\>.settings.json** is the workflow-specific settings file. This option is used for the build, ci and deploy workflows to determine artifacts and build numbers when running these workflows.

**.FSC-PS\\\<username\>.settings.json** is the user-specific settings file. This option is rarely used, but if you have special settings, which should only be used for one specific user (potentially in the local scripts), these settings can be added to a settings file with the name of the user followed by `.settings.json`.

**.FSC-PS\\environments.json** is the environment settings file. This settings file contains the list on the environments with the environment specific settings(branch, FSC version, etc.).

## Basic settings
| Name | Description | Default value |
| :-- | :-- | :-- |
| type | Specifies the type of project. Allowed values are **FSCM** or **Retail** or **Commerce** or **ECommerce**. This value comes with the default repository. | FSCM |
| companyName | Company name using for generate the package name.  | |
| buildVersion | The default D365 FSC version used to build and generate the package. Can be overriden by FSC-PS-Settings/environment/build/ci/deploy settings  | |
| buildPath | The FSC-PS system will copy the {github.workspace} into this folder and will do the build from it. The folder will be located inside C:\Temp\  | _bld |
| metadataPath | FSC specific. Specify the folder hat contains the FSC models  {github.workspace}\{metadataPath} | PackagesLocalDirectory |
| includeTestModel | FSC specific. Include unit test models into the package. Can be overriden by FSC-PS-Settings/environment/build/ci/deploy settings. | false |
| deployScheduleCron | CRON schedule for when deploy workflow should run. Default is execute each first minute of hour, only manual trigger. Build your CRON string here: https://crontab.guru | 1 * * * * |
| generatePackages | Option to generate a package after build. Often used in build, deploy and release workflows | true |
| uploadPackageToLCS | Option to upload generated package to the LCS after build and generate process. IMPORTANT!!! generatePackages option should be set to True  | false |
| exportModel | FSC specific. Option to generate axmodel file. IMPORTANT!!! generatePackages option should be set to True  | false |
| retailSDKZipPath | Retail specific. Optional. The path to the directory where RetailSDK archives will be stored  | C:\RSDK |
| retailSDKBuildPath | Retail specific. Optional. The path to the directory where RetailSDK will build the extension.  | C:\Temp\RetailSDK |
| deployOnlyNew | FSC/Retail specific. Deploy environments while schedule only if the related environment branch has changes yongest then latest deploy  | true |
| specifyModelsManually | FSC specific. If you want to build/deploy only specific models, set to true  | false |
| models | FSC specific. Comma delimited array of models.  | "" |
| deploymentScheduler | FSC/Retail specific. Enable/Disable the deployment schedule  | true |

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
| Name | Description | Default value |
| :-- | :-- | :-- |
| lcsEnvironmentId | The Guid of the LCS environment | |
| lcsProjectId | The ID of the LCS project | |
| lcsClientId | The ClientId of the azure application what has access to the LCS | |
| lcsUsernameSecretname | The github secret name that contains the username what has at least Owner access to the LCS project. It is a highly recommend to create a separate AAD user for this purposes. E.g. lcsadmin@contoso.com | AZ_TENANT_USERNAME |
| lcsPasswordSecretname | The github secret name that contains the password of the LCS user. | AZ_TENANT_PASSWORD |
| FSCPreviewVersionPackageId | The AssetId of the Preview package of the FSC. Depends on the FSC Version(version.default.json). | "" |
| FSCServiseUpdatePackageId | The AssetId of the Service Update (GA) package of the FSC. Depends on the FSC Version(version.default.json). | "" |
| FSCFinalQualityUpdatePackageId | The AssetId of the Final Quality Update (Latest) package of the FSC. Depends on the FSC Version(version.default.json). | "" |

### Azure settings
These Azure settings should contain the tenant configuration what will use by default for all deployments. Used for checking the VM status in the deploy workflow. AAD Application should have "DevTest labs" permitions for the Azure sebscription. Can be overrided in the environments settings.
| Name | Description | Default value |
| :-- | :-- |  :-- |
| azTenantId | The Guid of the Azure tenant  |  |
| azClientId | The Guid of the AAD registered application  |  |
| azClientsecretSecretname | The github secret name that contains ClientSecret of the registered application  | AZ_CLIENTSECRET |
| azVmname | The name of the Azure Virtual Machine. Should be specified in the .FSC-PS\environments.json settings  |  |
| azVmrg |  The name of the Azure Resouce Group contains the Virtual machine. Should be specified in the .FSC-PS\environments.json settings |  |

### Retail settings
These Retail settings should contain the RetailSDK settings. Can be overrided in the .FSC-PS\versions.json settings.
| Name | Description | Default value |
| :-- | :-- | :-- | 
| RetailSDKVersion | Retail specific. The RetailSDK version what will use to build the Retail extention. By default the settings from the versions.default.json will be used but can be overriden in .FSC-PS\versions.json file.  | |
| RetailSDKURL | Retail specific. The direct http link to do download the RetailSDK 7z archive. By default the settings from the versions.default.json will be used but can be overriden in .FSC-PS\versions.json file.  | |

### ECommerce settings
The ECommerce settings. Can be overrided in the .FSC-PS\versions.json settings.
| Name | Description | Default value |
| :-- | :-- | :-- | 
| ecommerceMicrosoftRepoUrl | ECommerce specific. The Msdyn365.Commerce.OnlineSDK repo URL what will use to build the ECommerce pacage. By default the settings from the versions.default.json will be used but can be overriden in .FSC-PS\versions.json file.  | |
| EcommerceMicrosoftRepoBranch | ECommerce specific. The Msdyn365.Commerce.OnlineSDK repo branch. By default the settings from the versions.default.json will be used but can be overriden in .FSC-PS\versions.json file.  | |

## Runtime generated settings
| Name | Description | Default value |
| :-- | :-- | :-- |
| currentBranch | The workflow execution branch name | {current execution branch} |
| sourceBranch | The branch used to build and generate the package. Using for deployment | {branch name from .FSC-PS\environments.json settings} |

## Basic Repository settings
The repository settings are only read from the repository settings file (.github\FSC-PS-Settings.json)

| Name | Description | Default value |
| :-- | :-- | :-- |
| templateUrl | Defines the URL of the template repository used to create this project and is used for checking and downloading updates to FSC-PS System files. | https://github.com/fscpscollaborative/fscps.fsctpl</br>https://github.com/fscpscollaborative/fscps.commercetpl |
| templateBranch | Defines the branchranch of the template repository used to create this project and is used for checking and downloading updates to FSC-PS System files. | main |
| runs-on | Specifies which github runner will be used for all jobs in all workflows (except the Update FSC-PS System Files workflow). The default is to use the GitHub hosted runner Windows-latest. You can specify a special GitHub Runner for the build job using the GitHubRunner setting. Read [this](SelfHostedGitHubRunner.md) for more information. | windows-latest |
| githubRunner | Specifies which github runner will be used for the build/ci/deploy/release job in workflows. This is the most time consuming task. By default this job uses the Windows-latest github runner (unless overridden by the runs-on setting). This settings takes precedence over runs-on so that you can use different runners for the build job and the housekeeping jobs. See runs-on setting. | windows-latest |

## Environments settings
| Name | Description | Default value |
| :-- | :-- | :-- |
| Name | The LCS environment name ||
| settings | The environment specific settings which will override the basic settings in the .\FSC-PS\settings.json file.  ||
| settings.buildVersion | The FSC version (e.g. 10.0.29). Will be used to build the package and deploy to this environment  | buildVersion value from the .\FSC-PS\settings.json file |
| settings.sourceBranch | The source branch name (e.g. main). Will be used to get the latest source code, build the package and deploy to this environment  | main |
| settings.lcsEnvironmentId | The LCS EnvironmentID. Will be used to identify the environment to deploy the package  | |
| settings.azVmname | The Azure VM name. Will be used to identify the current status of the VM and to Start or Stop it.  | |
| settings.azVmrg | The Azure VM ResourceGrop. Will be used to identify the current status of the VM and to Start or Stop it.  | |
| settings.cron | The Cron string. Will be used to identify the time to schedule the deployment. (UTC)  | |
| settings.deploy | Deploy environment while schedule  | true |
| settings.deployOnlyNew | Deploy environment while schedule only if the related branch has changes yongest then latest deploy  | true |
| settings.includeTestModel | FSC specific. Include unit test models into the package. | false |

## Advanced settings
| Name | Description | Default value |
| :-- | :-- | :-- |
| versioningStrategy |	under development | 0 |
| repoTokenSecretName | Specifies the name (**NOT the secret**) of the REPO_TOKEN secret. Default is REPO_TOKEN. FSC-PS for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as Personal Access Token with permission to modify workflows when running the Update FSC-PS System Files workflow. Read [this](UpdateFSC-PSSystemFiles.md) for more information. | REPO_TOKEN |
| failOn | Specifies what the pipeline will fail on. Allowed values are none, warning and error | error |
| codeSignDigiCertUrlSecretName<br />codeSignDigiCertPasswordSecretName | Specifying the secure URL from which your codesigning certificate pfx file can be downloaded and the password for this certificate. These settings specifies the names (**NOT the secrets**) of the code signing certificate url and password. Default is to look for secrets called codeSignDigiCertUrl and codeSignDigiCertPassword. Read [this](SetupCD.md) for more information. | codeSignDigiCertUrl<br />codeSignDigiCertPassword |

---
[back](/README.md)