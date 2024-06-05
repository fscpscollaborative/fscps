# #4 Setup self-hosted GitHub runners
*Prerequisites:* 
- A GitHub admin account.
- An Azure admin account.
- An LCS access.

1. Deploy new Build Azure VM or use the existing one.
2. Install the run github agent to this VM and specify the specific label to this runner.
3. Update .\FSC-PS\settings.json file:
~~~javascript
{
    "type":"FSCM",
    ....
    "githubRunner":"{SpecificLabel}",
    ....
}
~~~

4. Run [Update FSC-PS files](UpdateFSC-PS.md)

---
[back](/README.md)
