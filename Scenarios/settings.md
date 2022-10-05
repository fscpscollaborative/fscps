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
| templateUrl | Defines the URL of the template repository used to create this project and is used for checking and downloading updates to FSC-PS System files. | https://github.com/ciellosinc/FSC-PS-Template |
| templateBranch | Defines the branchranch of the template repository used to create this project and is used for checking and downloading updates to FSC-PS System files. | main |
| runs-on | Specifies which github runner will be used for all jobs in all workflows (except the Update FSC-PS System Files workflow). The default is to use the GitHub hosted runner Windows-latest. You can specify a special GitHub Runner for the build job using the GitHubRunner setting. Read [this](SelfHostedGitHubRunner.md) for more information. | windows-latest |
| githubRunner | Specifies which github runner will be used for the build/ci/deploy/release job in workflows. This is the most time consuming task. By default this job uses the Windows-latest github runner (unless overridden by the runs-on setting). This settings takes precedence over runs-on so that you can use different runners for the build job and the housekeeping jobs. See runs-on setting. | windows-latest |
| buildVersion | The default D365 FSC version used to build and generate the package. Can be overriden by FSC-PS-Settings/environment/build/ci/deploy settings  | |
| models | The models string array taking a part in the solution. Should be specified with comma delimeter. Example ("Contoso,ContosoTextExtension,ContosoExtension")| |
| buildPath | The FSC-PS system will copy the {github.workspace} into this folder and will do the build from it. The folder will be located inside C:\Temp\   | _bld |

## Runtime generated settings
| Name | Description | Default value |
| :-- | :-- | :-- |
| currentBranch | The workflow execution branch name | {current execution branch} |
| sourceBranch | The branch used to build and generate the package. Using for deployment | {branch name from environment settings} |
| |||

## Basic Repository settings
The repository settings are only read from the repository settings file (.github\FSC-PS-Settings.json)

| Name | Description |
| :-- | :-- |
| templateUrl | Defines the URL of the template repository used to create this project and is used for checking and downloading updates to FSC-PS System files. |
| currentSchedule | CRON schedule for when Current workflow should run. Default is no scheduled run, only manual trigger. Build your CRON string here: https://crontab.guru |
| runs-on | Specifies which github runner will be used for all jobs in all workflows (except the Update FSC-PS System Files workflow). The default is to use the GitHub hosted runner Windows-latest. You can specify a special GitHub Runner for the build job using the GitHubRunner setting. Read [this](SelfHostedGitHubRunner.md) for more information.
| githubRunner | Specifies which github runner will be used for the build job in workflows including a build job. This is the most time consuming task. By default this job uses the Windows-latest github runner (unless overridden by the runs-on setting). This settings takes precedence over runs-on so that you can use different runners for the build job and the housekeeping jobs. See runs-on setting.

## Advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| artifact | Determines the artifacts used for building and testing the app.<br />This setting can either be an absolute pointer to Business Central artifacts (https://... - rarely used) or it can be a search specification for artifacts (\<storageaccount\>/\<type\>/\<version\>/\<country\>/\<select\>/\<sastoken\>).<br />If not specified, the artifacts used will be the latest sandbox artifacts from the country specified in the country setting. | |
| updateDependencies | Setting updateDependencies to true causes FSC-PS to build your app against the first compatible Business Central build and set the dependency version numbers in the app.json accordingly during build. All version numbers in the built app will be set to the version number used during compilation. | false |
| generateDependencyArtifact | When this repository setting is true, CI/CD pipeline generates an artifact with the external dependencies used for building the apps in this repo. | false |

| versioningStrategy | The versioning strategy determines how versioning is performed in this project. The version number of an app consists of 4 tuples: **Major**.**Minor**.**Build**.**Revision**. **Major** and **Minor** are read from the app.json file for each app. **Build** and **Revision** are calculated. Currently 3 versioning strategies are supported:<br />**0** = **Build** is the **github [run_number](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** for the CI/CD workflow, increased by the **runNumberOffset** setting value (if specified). **Revision** is the **github [run_attempt](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** subtracted 1.<br />**1** = **Build** is the **github [run_id](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** for the repository. **Revision** is the **github [run_attempt](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context)** subtracted 1.<br />**2** = **Build** is the current date  as **yyyyMMdd**. **Revision** is the current time as **hhmmss**. Date and time are always **UTC** timezone to avoid problems during daylight savings time change. Note that if two CI/CD workflows are started within the same second, this could yield to identical version numbers from two different runs.<br />**+16** use **repoVersion** setting as **appVersion** (**Major** and **Minor**) for all apps | 0 |
| additionalCountries | This property can be set to an additional number of countries to compile, publish and test your app against during workflows. Note that this setting can be different in NextMajor and NextMinor workflows compared to the CI/CD workflow, by specifying a different value in a workflow settings file. | [ ] |
| keyVaultName | When using Azure KeyVault for the secrets used in your workflows, the KeyVault name needs to be specified in this setting if it isn't specified in the AZURE_CREDENTIALS secret. Read [this](UseAzureKeyVault.md) for more information. | |
| licenseFileUrlSecretName | Specify the name (**NOT the secret**) of the LicenseFileUrl secret. Default is LicenseFileUrl. FSC-PS for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as LicenseFileUrl when running the CI/CD workflow for AppSource Apps. Read [this](SetupCiCdForExistingAppSourceApp.md) for more information. | LicenseFileUrl |
| insiderSasTokenSecretName | Specifies the name (**NOT the secret**) of the InsiderSasToken secret. Default is InsiderSasToken. FSC-PS for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as InsiderSasToken for getting access to Next Minor and Next Major builds. | InsiderSasToken |
| ghTokenWorkflowSecretName | Specifies the name (**NOT the secret**) of the GhTokenWorkflow secret. Default is GhTokenWorkflow. FSC-PS for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use as Personal Access Token with permission to modify workflows when running the Update FSC-PS System Files workflow. Read [this](UpdateAlGoSystemFiles.md) for more information. | GhTokenWorkflow |
| adminCenterApiCredentialsSecretName | Specifies the name (**NOT the secret**) of the adminCenterApiCredentials secret. Default is adminCenterApiCredentials. FSC-PS for GitHub will look for a secret with this name in GitHub Secrets or Azure KeyVault to use when connecting to the Admin Center API when creating Online Development Environments. Read [this](CreateOnlineDevEnv2.md) for more information. | AdminCenterApiCredentials |
| installApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of either secure URLs or paths to folders or files relative to the project, where the CI/CD workflow can find and download the apps. The apps in installApps are downloaded and installed before compiling and installing the apps. | [ ] |
| installTestApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of either secure URLs or paths to folders or files relative to the project, where the CI/CD workflow can find and download the apps. The apps in installTestApps are downloaded and installed before compiling and installing the test apps. Adding a parantheses around the setting indicates that the test in this app will NOT be run, only installed. | [ ] |
| configPackages | An array of configuration packages to be applied to the build container before running tests. Configuration packages can be the relative path within the project or it can be STANDARD, EXTENDED or EVALUATION for the rapidstart packages, which comes with Business Central. | [ ] |
| configPackages.{country} | An array of configuration packages to be applied to the build container for country {country} before running tests. Configuration packages can be the relative path within the project or it can be STANDARD, EXTENDED or EVALUATION for the rapidstart packages, which comes with Business Central. | [ ] |
| installOnlyReferencedApps | By default, only the apps referenced in the dependency chain of your apps will be installed when inspecting the settings: InstallApps, InstallTestApps and appDependencyProbingPath. If you change this setting to false, all apps found will be installed. | true |
| enableCodeCop | If enableCodeCop is set to true, the CI/CD workflow will enable the CodeCop analyzer when building. | false |
| enableUICop | If enableUICop is set to true, the CI/CD workflow will enable the UICop analyzer when building. | false |
| customCodeCops | CustomCodeCops is an array of paths or URLs to custom Code Cop DLLs you want to enable when building. | [ ] |
| failOn | Specifies what the pipeline will fail on. Allowed values are none, warning and error | error |
| rulesetFile | Filename of the custom ruleset file | |
| codeSignCertificateUrlSecretName<br />codeSignCertificatePasswordSecretName | When developing AppSource Apps, your app needs to be code signed and you need to add secrets to GitHub secrets or Azure KeyVault, specifying the secure URL from which your codesigning certificate pfx file can be downloaded and the password for this certificate. These settings specifies the names (**NOT the secrets**) of the code signing certificate url and password. Default is to look for secrets called CodeSignCertificateUrl and CodeSignCertificatePassword. Read [this](SetupCiCdForExistingAppSourceApp.md) for more information. | CodeSignCertificateUrl<br />CodeSignCertificatePassword |
| applicationInsightsConnectionStringSecretName | This setting specifies the name (**NOT the secret**) of a secret containing the application insights connection string for the apps. | applicationInsightsConnectionString |
| storageContextSecretName | This setting specifies the name (**NOT the secret**) of a secret containing a json string with StorageAccountName, ContainerName, BlobName and StorageAccountKey or SAS Token. If this secret exists, FSC-PS will upload builds to this storage account for every successful build.<br />The BcContainerHelper function New-ALGoStorageContext can create a .json structure with this content. | StorageContext |
| alwaysBuildAllProjects | This setting only makes sense if the repository is setup for multiple projects.<br />Standard behavior of the CI/CD workflow is to only build the projects, in which files have changes when running the workflow due to a push or a pull request | false |
| skipUpgrade | This setting is used to signal to the pipeline to NOT run upgrade and ignore previous releases of the app. | false |
| cacheImageName | When using self-hosted runners, cacheImageName specifies the prefix for the docker image created for increased performance | my |
| cacheKeepDays | When using self-hosted runners, cacheKeepDays specifies the number of days docker image are cached before cleaned up when running the next pipeline.<br />Note that setting cacheKeepDays to 0 will flush the cache before every build and will cause all other running builds using agents on the same host to fail. | 3 |
| BcContainerHelperVersion | This setting can be set to a specific version (ex. 3.0.8) of BcContainerHelper to force FSC-PS to use this version. **latest** means that FSC-PS will use the latest released version. **preview** means that FSC-PS will use the latest preview version. **dev** means that FSC-PS will use the dev branch of containerhelper. | latest (or preview for FSC-PS preview) |


