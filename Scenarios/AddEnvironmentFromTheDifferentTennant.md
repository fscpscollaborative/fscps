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
~~~javascipt
[
    .....,
    {
        "name":"ClientContoso-UAT",
        "settings":{
            "buildVersion": "10.0.27",
            "sourceBranch": "release",
            "lcsEnvironmentId": "26578974-0040-4d48-a09f-ff2235042e2c",
            "lcsProjectId": 1234568,
            "lcsClientId": "110ebf68-a86d-4392-ae38-57b0040ee3fc",
            "lcsUsernameSecretname": "AZ_ANOTHER_TENANT_USERNAME",
            "lcsPasswordSecretname": "AZ_ANOTHER_TENANT_PASSWORD",
            "azTenantId": "a86db6ec-0a2a-4f60-8ca1-eeaab338ae38",
            "azClientId" : "110ebf68-a86d-4392-ae38-57b0040ee3fc",
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