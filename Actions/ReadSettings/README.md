# :rocket: Action 'ReadSettings' 
Read settings for FSC-PS workflows 
## :wrench: Parameters 
## :arrow_down: Inputs 
### get (Default: '') 
 Specifies which properties to get from the settings file, default is all 

### environment (Default: '') 
 Merge settings from specific environment 

### actor (Default: '${{ github.actor }}') 
 The GitHub actor running the action 

### token (Default: '${{ github.token }}') 
 The GitHub token running the action 

### version (Default: '') 
 The Dynamics Application Version 

## :arrow_up: Outputs 
### type (Default: '') 
 Repo type 

### EnvironmentsJson (Default: '') 
 Environments in compressed Json format 

### GitHubRunnerJson (Default: '') 
 GitHubRunner in compressed Json format 

### source_branch (Default: '') 
 Source branch 

### VersionsJson (Default: '') 
 Versions in compressed Json format 

### SettingsJson (Default: '') 
 Settings in compressed Json format 


