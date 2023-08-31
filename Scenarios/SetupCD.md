# #3 Setup CD
*Prerequisites:* 
- A GitHub admin account.
- An AAD admin account.
- An LCS admin access.

1. Register AAD application with LCS permissions.
2. Assign DevTestLabs role in the Subscription to this application.
3. Generate Client Secret to the registered application
4. Register secrets to the GitHub repo:
- AZ_TENANT_USERNAME - Set the username of the User with tenant administrator permissions.
- AZ_TENANT_PASSWORD - Set password of the User with tenant administrator permissions.
- AZ_CLIENTSECRET - Set the ClientSecret of the registered application.
5. Update .\FSC-PS\settings.json file with the folowing settings:
~~~javascript
{
    "type":"FSCM",
    "packageName": "ContosoExtension",
    "buildVersion": "10.0.29",
    "ciBranches": "main,release",
    "lcsProjectId": 1234567,
    "lcsClientId": "{SetRegisteredAppId-GUID}",
    "azTenantId": "{SetYourTenantId-GUID}",
    "azClientId": "{SetRegisteredAppId-GUID}"
}
~~~

**NOTE:** lcsProjectId - Paste the LCS projectID. Please refer to [this description](settings.md) to find more details.

6. Login to the LCS and deploy new or use the existing one environment.
7. Update .\FSC-PS\environments.json file
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
            "cron":"0 21 * * *"
        }
    }
]
~~~

**NOTE:** "cron" - It meant that the environment will deploy at 21:00 PM UTC. Please refer to [this description](settings.md) to find more details.

8. Run [Update FSC-PS files](UpdateFSC-PS.md)
9. Deploy [D365FSC. Deploy the code to the environment ](Scenarios/DeployCode.md)

---
[back](/README.md)
