# :rocket: Action 'CheckForUpdates' 
Check for updates to FSC-PS system files 
## :wrench: Parameters 
## :arrow_down: Inputs 
### templateBranch (Default: '') 
 Branch in template repository to use for the update (default is the default branch) 

### settingsJson (Default: '') 
 Settings from repository in compressed Json format 

### type (Default: 'FSCM') 
 Repo type 

### update (Default: 'N') 
 Set this input to Y in order to update FSC-PS System Files if needed 

### directCommit (Default: '') 
 Direct Commit 

### templateUrl (Default: '') 
 URL of the template repository (default is the template repository used to create the repository) 

### actor (Default: '${{ github.actor }}') 
 The GitHub actor running the action 

### token (Default: '${{ github.token }}') 
 The GitHub token running the action 

### secretsJson (Default: '') 
 Secrets from repository in compressed Json format 


