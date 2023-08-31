# #8 D365FSC. Build or deploy a specific model(`s)
*Prerequisites:* 
- A GitHub account.
If you need to deploy a specific model to the environment do the next:

1. Add "specifyModelsManually" to the specific environment in the .\FSC-PS\environments.json file:
~~~javascript
[
    {
        "name":"Contoso-QA",
        "settings":{
            "buildVersion": "10.0.29",
            "sourceBranch": "main",
            "lcsEnvironmentId": "{SetLCSEnvironmentId-GUID}",
            "azVmname" : "{SetAzurVMName}",
            "azVmrg" : "{SetAzureVMResourceGrouName}",
            "cron":"0 21 * * *",
            "specifyModelsManually":true,
            "models":"Model1,Model2"
        }
    }
]
~~~

Now, anytime when you execute the Deploy workflow for this environment, the FSC-PS will take specified models, build, include it into the deployable package and deploy to the environment.


If you need to build a specific model do the next:

1. Add "specifyModelsManually" to the .\github\build.settings.json and/or to the .\github\ci.settings.json and/or to the .\github\release.settings.json file:
~~~javascript
{
    ....
    "specifyModelsManually":true,
    "models":"Model1,Model2",
    ....
}

~~~

Now, anytime when you execute the BUILD/CI/RELEASE workflow, the FSC-PS will take specified models, for build/release/ci process.



If you need to use a specific model in all workflows:

1. Add "specifyModelsManually" to the .\FSC-PS\settings.json file:
~~~javascript
{
    ....
    "specifyModelsManually":true,
    "models":"Model1,Model2",
    ....
}

~~~

Now, anytime when you execute the BUILD/CI/RELEASE/DEPLOY workflows, the FSC-PS will take specified models, for these processes.

---
[back](/README.md)