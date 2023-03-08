# :rocket: Action 'ReadSettings' 
Read settings for FSC-PS workflows 
## :wrench: Parameters 
## :arrow_down: Inputs 
### environment (Default: '') 
 Merge settings from specific environment 

### token (Default: '${{ github.token }}') 
 The GitHub token running the action 

### version (Default: '') 
 The Dynamics Application Version 

### actor (Default: '${{ github.actor }}') 
 The GitHub actor running the action 

### get (Default: '') 
 Specifies which properties to get from the settings file, default is all 

## :arrow_up: Outputs 
### GitHubRunnerJson (Default: '') 
 GitHubRunner in compressed Json format 

### source_branch (Default: '') 
 Source branch 

### EnvironmentsJson (Default: '') 
 Environments in compressed Json format 

### type (Default: '') 
 Repo type 

### VersionsJson (Default: '') 
 Versions in compressed Json format 

### SettingsJson (Default: '') 
 Settings in compressed Json format 


