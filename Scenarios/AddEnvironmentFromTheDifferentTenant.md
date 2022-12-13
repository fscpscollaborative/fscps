# #6 Add the environment from the different tenant
*Prerequisites:* 
- A GitHub admin account.
- An Azure admin account.
- An LCS access.



1. Register secrets from another tenant to the GitHub repo:
- AZ_ANOTHER_TENANT_USERNAME - Set the username of the User with tenant administrator permissions.
- AZ_ANOTHER_TENANT_PASSWORD - Set password of the User with tenant administrator permissions.
- AZ_ANOTHER_CLIENTSECRET - Set the ClientSecret of the registered application.

2. Update .\FSC-PS\environments.json file with the folowing settings:
~~~javascript
[
    .....,
    {
        "name":"ClientContoso-UAT",
        "settings":{
            "buildVersion": "10.0.27",
            "sourceBranch": "release",
            "lcsEnvironmentId": "{SetLCSEnvironmemntID}",
            "lcsProjectId": 1234568,
            "lcsClientId": "{SetAzureRegisteredAppId-GUID}",
            "lcsUsernameSecretname": "AZ_ANOTHER_TENANT_USERNAME",
            "lcsPasswordSecretname": "AZ_ANOTHER_TENANT_PASSWORD",
            "azTenantId": "{SetAnotherTenantId-GUID}",
            "azClientId" : "{SetAzureRegisteredAppId-GUID}",
            "azClientsecretSecretname" : "AZ_ANOTHER_CLIENTSECRET",
            "azVmname" : "ClientContoso-UAT-1",
            "azVmrg" : "ClientContoso-UAT",
            "cron":"0 23 * * *",
            "includeTestModel":true
        }
    },
    .....
]
~~~

3. Run [Update FSC-PS files](UpdateFSC-PS.md)

---
[back](/README.md)