# :rocket: Action 'CheckForUpdates' 
Check for updates to FSC-PS system files 
## :wrench: Parameters 
## :arrow_down: Inputs 
### type (Default: 'FSCM') 
 Repo type 

### update (Default: 'N') 
 Set this input to Y in order to update FSC-PS System Files if needed 

### templateUrl (Default: '') 
 URL of the template repository (default is the template repository used to create the repository) 

### settingsJson (Default: '') 
 Settings from repository in compressed Json format 

### secretsJson (Default: '') 
 Secrets from repository in compressed Json format 

### templateBranch (Default: '') 
 Branch in template repository to use for the update (default is the default branch) 

### token (Default: '${{ github.token }}') 
 The GitHub token running the action 

### directCommit (Default: 'N') 
 Direct Commit (Y/N) 

### actor (Default: '${{ github.actor }}') 
 The GitHub actor running the action 


