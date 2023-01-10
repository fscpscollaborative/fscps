# #5 D365FSC. Include Test model into the deployable package
*Prerequisites:* 
- A GitHub account.
If you need to always deploy your test model to the specific environment do the next:

1. Add "includeTestModel" to the specific environment in the .\FSC-PS\environments.json file:
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
            "includeTestModel":true
        }
    }
]
~~~

Now, anytime when you execute the Deploy workflow for this environment, the FSC-PS will take your Test model, build, include it into the deployable package and deploy to the environment.

---
[back](/README.md)