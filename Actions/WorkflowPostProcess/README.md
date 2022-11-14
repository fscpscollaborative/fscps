#Action WorkflowPostProcess 
##Parameter secretsJson 
###Description Secrets from repository in compressed Json format 
###Default {"insiderSasToken":"","licenseFileUrl":"","CodeSignCertificateUrl":"","CodeSignCertificatePw":"","KeyVaultCertificateUrl":"","KeyVaultCertificatePw":"","KeyVaultClientId":"","applicationInsightsConnectionString": ""} 

##Parameter token 
###Description The GitHub token running the action 
###Default ${{ github.token }} 

##Parameter remove_current 
###Description The GitHub actor running the action 
###Default  

##Parameter settingsJson 
###Description Settings from repository in compressed Json format 
###Default  


