# #2 Setup CI
*Prerequisites:* 
- A GitHub account.

![Created repo](/Scenarios/images/2b.png)
1. Done [scenario 1](SetupRepo.md)

2. Update settings file in the .FSC-PS folder.
~~~javascript
{
    "packageName": "ContosoExtension",
    "buildVersion": "10.0.29",
    "ciBranches": "main,release",
    "useLocalNuGetStorage":true
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

4. Execute
[Update FSC-PS files](UpdateFSC-PS.md)

5. Execute CI workflow
![Execute CI](/Scenarios/images/2a.png)

6. Waiting for result
![Execution done](/Scenarios/images/2c.png)

7. Setup security rules for branch
![Execution done](/Scenarios/images/2d.png)

---
[back](/README.md)
