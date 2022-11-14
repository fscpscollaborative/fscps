# Action 'RunPipeline' 
## Parameter 'settingsJson' 
### Description 
 'Settings from repository in compressed Json format' 
### Default value 
 '' 

## Parameter 'version' 
### Description 
 'The Dynamics Application Version' 
### Default value 
 '' 

## Parameter 'type' 
### Description 
 'The application type. FSCM or Commerce' 
### Default value 
 'FSCM' 

## Parameter 'environment_name' 
### Description 
 'The Dynamics Environment Name' 
### Default value 
 '' 

## Parameter 'actor' 
### Description 
 'The GitHub actor running the action' 
### Default value 
 '${{ github.actor }}' 

## Parameter 'secretsJson' 
### Description 
 'Secrets from repository in compressed Json format' 
### Default value 
 '{"insiderSasToken":"","licenseFileUrl":"","CodeSignCertificateUrl":"","CodeSignCertificatePw":"","KeyVaultCertificateUrl":"","KeyVaultCertificatePw":"","KeyVaultClientId":"","applicationInsightsConnectionString": ""}' 

## Parameter 'token' 
### Description 
 'The GitHub token running the action' 
### Default value 
 '${{ github.token }}' 


