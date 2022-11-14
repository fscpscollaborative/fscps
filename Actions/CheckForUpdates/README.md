#Action CheckForUpdates 
##Parameter directCommit 
###Description Direct Commit (Y/N) 
###Default N 

##Parameter update 
###Description Set this input to Y in order to update AL-Go System Files if needed 
###Default N 

##Parameter settingsJson 
###Description Settings from repository in compressed Json format 
###Default  

##Parameter templateBranch 
###Description Branch in template repository to use for the update (default is the default branch) 
###Default  

##Parameter type 
###Description Repo type 
###Default FSCM 

##Parameter actor 
###Description The GitHub actor running the action 
###Default ${{ github.actor }} 

##Parameter secretsJson 
###Description Secrets from repository in compressed Json format 
###Default  

##Parameter templateUrl 
###Description URL of the template repository (default is the template repository used to create the repository) 
###Default  

##Parameter token 
###Description The GitHub token running the action 
###Default ${{ github.token }} 


