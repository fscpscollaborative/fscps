# FSC-PS for GitHub
:rocket: FSC-PS for GitHub is a set of GitHub templates and actions, which can be used to setup and maintain professional DevOps processes for your Dynamics 365 FSC and Commerce projects.

The goal is that people who have created their GitHub repositories based on the FSC-PS templates, can maintain these repositories and stay current just by running a workflow, which updates their repositories. This includes necessary changes to scripts and workflows to cope with new features and functions.

The template repository to use as starting point are:
- https://github.com/ciellosinc/FSC-PS.FSC is the GitHub repository template for D365 FSC Extenstions. This is your starting point.
- https://github.com/ciellosinc/FSC-PS.Commerce is the GitHub repository template for D365 Commerce Extenstions. This is your starting point.

The below usage scenarios takes you through how to get started and how to perform the most common tasks.

Usage scenarios:
1. [Set up repository](Scenarios/SetupRepo.md)
2. [Set up CI](Scenarios/SetupCI.md)
3. [Set up CD](Scenarios/SetupCD.md)
4. [Set up your own GitHub runner to increase build performance](Scenarios/SelfHostedGitHubRunner.md)
5. [Update FSC-PS files](Scenarios/UpdateFSC-PS.md)
6. [Add environment from the different tenant](Scenarios/AddEnvironmentFromTheDifferentTenant.md)
7. [D365FSC. Include Test model into the deployable package ](Scenarios/IncludeTestModel.md)

**Note:** Please refer to [this description](Scenarios/settings.md) to learn about the settings file and how you can modify default behaviors.
# This project
This project in the main source repository for FSC-PS for GitHub. This project is deployed on every release to a branch in the following repositories:

- https://github.com/ciellosinc/FSC-PS.FSC is the GitHub repository template for D365 FSC Extenstions. This is your starting point.
- https://github.com/ciellosinc/FSC-PS.Commerce is the GitHub repository template for D365 Commerce Extenstions. This is your starting point.
- https://github.com/ciellosinc/FSC-PS-Actions is the GitHub repository containing the GitHub Actions used by the template above.
