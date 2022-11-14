#Action RunPipeline 
##Parameter settingsJson 
###Description Settings from repository in compressed Json format 
###Default  

##Parameter version 
###Description The Dynamics Application Version 
###Default  

##Parameter type 
###Description The application type. FSCM or Commerce 
###Default FSCM 

##Parameter environment_name 
###Description The Dynamics Environment Name 
###Default  

##Parameter actor 
###Description The GitHub actor running the action 
###Default ${{ github.actor }} 

##Parameter secretsJson 
###Description Secrets from repository in compressed Json format 
###Default {"insiderSasToken":"","licenseFileUrl":"","CodeSignCertificateUrl":"","CodeSignCertificatePw":"","KeyVaultCertificateUrl":"","KeyVaultCertificatePw":"","KeyVaultClientId":"","applicationInsightsConnectionString": ""} 

##Parameter token 
###Description The GitHub token running the action 
###Default ${{ github.token }} 


