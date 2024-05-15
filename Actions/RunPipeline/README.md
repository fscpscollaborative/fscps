# :rocket: Action 'RunPipeline' 
Run pipeline in FSC-PS repository 
## :wrench: Parameters 
## :arrow_down: Inputs 
### secretsJson (Default: '{"insiderSasToken":"","licenseFileUrl":"","codeSignDigiCertUrl":"","codeSignDigiCertPw":""}') 
 Secrets from repository in compressed Json format 

### environment_name (Default: '') 
 The Dynamics Environment Name 

### type (Default: 'FSCM') 
 The application type. FSCM/Commerce/ECommerce 

### version (Default: '') 
 The Dynamics Application Version 

### token (Default: '${{ github.token }}') 
 The GitHub token running the action 

### actor (Default: '${{ github.actor }}') 
 The GitHub actor running the action 

### settingsJson (Default: '') 
 Settings from repository in compressed Json format 

## :arrow_up: Outputs 
### modelfile_path (Default: '') 
 Modelfile path 

### package_path (Default: '') 
 Package path 

### package_name (Default: '') 
 Package name 

### artifacts_list (Default: '') 
 Artifacts folder path 

### artifacts_path (Default: '') 
 Artifacts folder path 


