# :rocket: Action 'RunPipeline' 
Run pipeline in FSC-PS repository 
## :wrench: Parameters 
## :arrow_down: Inputs 
### settingsJson (Default: '') 
 Settings from repository in compressed Json format 

### token (Default: '${{ github.token }}') 
 The GitHub token running the action 

### environment_name (Default: '') 
 The Dynamics Environment Name 

### version (Default: '') 
 The Dynamics Application Version 

### secretsJson (Default: '{"insiderSasToken":"","licenseFileUrl":"","CodeSignCertificateUrl":"","CodeSignCertificatePw":""}') 
 Secrets from repository in compressed Json format 

### actor (Default: '${{ github.actor }}') 
 The GitHub actor running the action 

### type (Default: 'FSCM') 
 The application type. FSCM/Retail/ECommerce 

## :arrow_up: Outputs 
### package_path (Default: '') 
 Package path 

### artifacts_path (Default: '') 
 Artifacts folder path 

### artifacts_list (Default: '') 
 Artifacts folder path 

### modelfile_path (Default: '') 
 Modelfile path 

### package_name (Default: '') 
 Package name 


