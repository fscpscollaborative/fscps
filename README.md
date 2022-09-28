# FSCM-PS for GitHub
FSCM-PS for GitHub is a set of GitHub templates and actions, which can be used to setup and maintain professional DevOps processes for your Dynamics FSCM and Commerce projects.

The goal is that people who have created their GitHub repositories based on the FSCM templates, can maintain these repositories and stay current just by running a workflow, which updates their repositories. This includes necessary changes to scripts and workflows to cope with new features and functions.

The template repository to use as starting point are:
- https://github.com/ciellos-dev/FSCM-PS-Template is the GitHub repository template for FSCM or Commerce Extenstions. This is your starting point.

The below usage scenarios takes you through how to get started and how to perform the most common tasks.

Usage scenarios:
1. [Set up CI/CD for an existing per tenant extension (BingMaps)](Scenarios/SetupCiCdForExistingPTE.md)
2. [Set up your own GitHub runner to increase build performance](Scenarios/SelfHostedGitHubRunner.md)


**Note:** Please refer to [this description](Scenarios/settings.md) to learn about the settings file and how you can modify default behaviors.
# This project
This project in the main source repository for FSCM-PS for GitHub. This project is deployed on every release to a branch in the following repositories:

- https://github.com/ciellos-dev/FSCM-PS-Template is the GitHub repository template for FSCM or Commerce Extenstions. This is your starting point.
- https://github.com/ciellos-dev/FSCM-PS-Actions is the GitHub repository containing the GitHub Actions used by the template above.
