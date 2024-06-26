# #1 Set up repository
*Prerequisites:* 
- A GitHub account.


1. Navigate to https://github.com/fscpscollaborative/fscps.fsctpl or https://github.com/fscpscollaborative/fscps.commercetpl or https://github.com/fscpscollaborative/fscps.ecommercetpl and then choose **Use this template**.
![Use this template](/Scenarios/images/1a.png)
1. Enter **appName** as repository name and select **Create Repository from template**.
![Add repo](/Scenarios/images/1b.png)
![Added repo](/Scenarios/images/1e.png)
1. Generate REPO_TOKEN secret.

### Minimun set of permisions
- repo *
- admin:public_key *
- notifications
- user *
- project *

![Create_Token](/Scenarios/images/1c.png)

![Create_Secret](/Scenarios/images/1f.png)
1. Under **Actions** select the **(IMPORT)** workflow and choose **Run workflow**.
1. In the **Direct download URL** field, paste in the direct download URL of the source code 7z archive.
1. Wait a workflow completion
![Sources imported](/Scenarios/images/2b.png)
1. Use [Setup CI](SetupCI.md), [Setup CD](SetupCD.md).


---
[back](/README.md)
