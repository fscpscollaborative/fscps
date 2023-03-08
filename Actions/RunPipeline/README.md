# :rocket: Action 'RunPipeline' 
Run pipeline in FSC-PS repository 
## :wrench: Parameters 
## :arrow_down: Inputs 
### environment_name (Default: '') 
 The Dynamics Environment Name 

### actor (Default: '${{ github.actor }}') 
 The GitHub actor running the action 

### token (Default: '${{ github.token }}') 
 The GitHub token running the action 

### version (Default: '') 
 The Dynamics Application Version 

### type (Default: 'FSCM') 
 The application type. FSCM/Retail/ECommerce 

### settingsJson (Default: '') 
 Settings from repository in compressed Json format 

### secretsJson (Default: '{"insiderSasToken":"","licenseFileUrl":"","CodeSignCertificateUrl":"","CodeSignCertificatePw":""}') 
 Secrets from repository in compressed Json format 

## :arrow_up: Outputs 
### package_path (Default: '') 
 Package path 

### package_name (Default: '') 
 Package name 

### modelfile_path (Default: '') 
 Modelfile path 

### artifacts_path (Default: '') 
 Artifacts folder path 

### artifacts_list (Default: '') 
 Artifacts folder path 
