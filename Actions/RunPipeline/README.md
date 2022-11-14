# :rocket: Action 'RunPipeline' 
Run pipeline in FSC-PS repository 
## :wrench: Parameters 
## :arrow_down: Inputs 
### settingsJson (Default: '') 
 Settings from repository in compressed Json format 

### version (Default: '') 
 The Dynamics Application Version 

### type (Default: 'FSCM') 
 The application type. FSCM or Commerce 

### environment_name (Default: '') 
 The Dynamics Environment Name 

### actor (Default: '${{ github.actor }}') 
 The GitHub actor running the action 

### secretsJson (Default: '{"insiderSasToken":"","licenseFileUrl":"","CodeSignCertificateUrl":"","CodeSignCertificatePw":"","KeyVaultCertificateUrl":"","KeyVaultCertificatePw":"","KeyVaultClientId":"","applicationInsightsConnectionString": ""}') 
 Secrets from repository in compressed Json format 

### token (Default: '${{ github.token }}') 
 The GitHub token running the action 

## :arrow_up: Outputs 
### package_path (Default: '') 
 Package path 

### package_name (Default: '') 
 Package name 

### artifacts_list (Default: '') 
 Artifacts folder path 

### artifacts_path (Default: '') 
 Artifacts folder path 

### modelfile_path (Default: '') 
 Modelfile path 


