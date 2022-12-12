# #2 Setup CI
*Prerequisites:* 
- A GitHub account.

![Created repo](/Scenarios/images/2a.png)
1. Done [scenario 1](SetupRepo.md)

2. Update settings file in the .FSC-PS folder.
~~~javascript
{
    "packageName": "ContosoExtension",
    "buildVersion": "10.0.29"
}
~~~
Please find setup details [here](settings.md)

3. Update versions file
~~~javascript
[
    {
      "version": "10.0.29",
      "data":{
          "PlatformVersion": "7.0.6545.43",
          "AppVersion": "10.0.1326.46"
        }
    }
]
~~~
**NOTE** If you have some specific versions different with version.default, you can override them inside the versions.json file
Please find setup details [here](settings.md)

4. Execute CI workflow

---
[back](/README.md)
