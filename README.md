# Bug-Fix-on +AGIC + AKS-Kubenet-

This code was used to evaluate and confirm a claim that AGIC is unable to associate AKS route table to application gateway Subnet when one setup networking between AKS and Application gateway .
Accoding to MS documnentation, if you are using Kubenet network plugin, AGIC associate the AKS route table to the application gateway else you will get a 502 error code because the Application gateway does not have the route to the pod application.

* After deployment we confirmed that the AGIC did not associate the AKS route table to the application gateway as stated in this documentation https://azure.github.io/application-gateway-kubernetes-ingress/how-tos/networking/#with-kubenet 
* Going through the logs from the AGIC ,we could see that there is a permission issue and that is the root cause of this issue. The error message says ** The client '656df160-edbb-4963-85d4-3c56a9e60500' with object id '656df160-edbb-4963-85d4-3c56a9e60500' has permission to perform action 'Microsoft.Network/virtualNetworks/subnets/write' on scope '/subscriptions/309065ca-a060-4592-8096-b74694126b61/resourceGroups/bug-report-rg/providers/Microsoft.Network/virtualNetworks/bug-report-vnet/subnets/ag'; however, it does not have permission to perform action 'Microsoft.Network/networkSecurityGroups/join/action' on the linked scope(s) '/subscriptions/309065ca-a060-4592-8096-b74694126b61/resourceGroups/bug-report-rg/providers/Microsoft.Network/networkSecurityGroups/bug-report-ag-nsg' or the linked scope(s) are invalid."] 
* Note that If the virtual network Application Gateway is deployed into doesn't reside in the same resource group as the AKS nodes, you will need to ensure the identity used by AGIC has the Microsoft.Network/virtualNetworks/subnets/join/action permission. To do so, you may assign the built-in Network Contributor (as the built-in role Network role already support this permission) to the managed identity used by AGIC on the subnet the Application Gateway is deployed into. 
* According to the documentation When AGIC starts up, it checks the AKS node resource group for the existence of the route table. If it exists, AGIC will try to assign the route table to the Application Gateway's subnet, given it doesn't already have a route table. 

* We ran the following to grant the object ID (309065ca-a060-4592-8096-b74694126b61) the permissions for the application gateways subnet.
 
 appGatewayId="APPGW URI"
 
 Identity="<OBJECT_ID>"

### Get Application Gateway subnet id
appGatewaySubnetId=$(az network application-gateway show --ids $appGatewayId -o tsv --query "gatewayIPConfigurations[0].subnet.id")
 
### Assign network contributor role for identity to subnet that contains the Application Gateway
echo "Assigning Network Contributor role to identity $Identity to subnet $appGatewaySubnetId"
az role assignment create --assignee $Identity --scope $appGatewaySubnetId --role "Network Contributor"

Please be aware that it may take 24 hours for this permission to take effect. However it did not resolve the issue

Finally To fix this we manually add the route table using the powershell command below.

aksClusterName="<aksClusterName>"
aksResourceGroup="<aksResourceGroup>"
appGatewayName="<appGatewayName>"
appGatewayResourceGroup="<appGatewayResourceGroup>"
 
### find route table used by aks cluster
nodeResourceGroup=$(az aks show -n $aksClusterName -g $aksResourceGroup -o tsv --query "nodeResourceGroup")
routeTableId=$(az network route-table list -g $nodeResourceGroup --query "[].id | [0]" -o tsv)
 
### get the application gateway's subnet
appGatewaySubnetId=$(az network application-gateway show -n $appGatewayName -g $appGatewayResourceGroup -o tsv --query "gatewayIPConfigurations[0].subnet.id")
 
### associate the route table to Application Gateway's subnet
az network vnet subnet update \
--ids $appGatewaySubnetId
--route-table $routeTableId
