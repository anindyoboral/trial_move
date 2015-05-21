public class AddressCheckInteractive_Controller{

    //Author:         Jan Selis, Synergy2core BVBA
    //Company:        4C Consulting, Stationsstraat 60/5, 2800 Mechelen
    //Date:           2013-05-04 (creation)
    //Description:    Controller of the AddressCheckInteractive page.
    //                This page is used to allow an Address check in an interactive way. It is a complement to the non-interactive address check
    //                realized through the trigger trPerformAction (with Actions 'NINAS...'.
    //               
    //                The way it functions:
    //                - the page can be called from a button on the Detail page of an Address__c record or from a visualforce page (e.g. the eSOF page)
    //                  It is always called from an existing Address__c record. Remark: the page will work if called with no Id specified, the user
    //                  needs to fill the address data first and can then do address checks on that address, but upon save a new and unlinked Address__c
    //                  record will be inserted.
    //                  (future extension: call the page by passing the address fields via URL query parameters, and upon Save, return to the calling page
    //                   passing along the correct version of the address. Requires putting this controller as second controller in that calling page.)
    //                - The original data are then stored in an Address__c object that is not modified anymore
    //                - These data are also put as default data in a second Address__c object that is linked to editable input fields on the page.
    //                  The user can edit these data via direct input in the input fields, or by selecting a radio button in the list of potential matching 
    //                  addresses (see further).
    //                  Whenever these data are modified to be different from the original, the input text turns red and the original version appears right
    //                  of the input field.
    //                - both in original and edit object, all [A], [C] and [E] fields are shown.
    //                  (see HTTPRequestNINAS.summarizeAddrResponse function comments for list of [A], [C] and [E] fields: 
    //                   A = input address, which is also returned by retrieveAddresses, C = Id's output from retrieveAddresses, E = output from retrieveNetworkDetails.
    //                   However, [C] and [E] fields are disabled. 
    //                   TO BE DISCUSSED: should CanonicalAddressId be enabled?
    //                   TO BE DISCUSSED: should the [A] fields be disabled as soon as CanonicalAddressId is filled?
    //                - when the user clicks on the button 'Check!', the following happens:
    //                     * if the retrieveAddresses was not done yet on the data in the edit fields, do retrieveAddresses and build up list of resulting
    //                       addresses and show on screen (different colours for non-validated or non-verified addresses).
    //                       Next to each address (first column) a radio-button is shown, non-selected. When one of the radio-buttons is selected, the fields of
    //                       that address result are copied into the edit fields on top (for those that change a value compared to the orig, they become red)
    //                       Next also to each addresses (between the retrieveAddress and retrieveNetworkDetails fields) is a list of checkboxes 'netw chk',
    //                       all unchecked.
    //                     * if the retrieveAddresses was already done on those fields (with the content they still have), do not repeat the retrieveAddresses,
    //                       but for each of the checked 'netw chk' address results, and if it wasn't done successfully yet, perform a retrieveNetworkDetails, 
    //                       and show the result.
    //                     * future extension: if the retrieveAddresses was already done, but with different content of the edit fields, only remove from the old result the records
    //                       where a no network check was done, repeat the retrieveAddresses, remove from those the results that are already in the network checked
    //                       results, and show the whole lot.
    //                       There would also be a button 'clear results' that would clear all address results (same state as 'retrieveAddresses was not done yet').
    //                - When clicking on a 'netw chk' checkbox, run the retrieveNetworkDetails immediately via ajax. This way, the user can launch
    //                  several requests concurrently and see the results appearing as they are retrieved.
    //                - when the user clicks on a radio button of one of the address results:
    //                     * [A] fields are copied to the corresponding Edit fields
    //                     * [C] fields are also copied to the corresponding Edit fields. If the CanonicalAddressId__c changes as a result of that, 
    //                           clear all [E] fields. (better: if CanonicalAddressId__c changes clear [C] and [E] fields, except of course CanonicalAddressId__c itself).
    //                     * [E] fields are copied to the corresponding Edit fields if a retrieveNetworkDetails 
    //                - when clicking Save: the values of the Edit fields are saved to the Address__c record with the given Id (originally passed to the page) and the page
    //                  is redirected to the calling page. 
    //                  Future extension: upon Save, stay on the page (turn Cancel into Close button) and reset the orig version of the address to the saved version. The user
    //                  can then continue to do checks comparing with the just saved version.
    //                - there is also a Cancel button.

    /////////////////
    //helper class //   to encapsulate retrieve results (which are Address__c objects) (checkbox,...)
    /////////////////
    public class CAddressResult {
        public Integer index {get;set;} //position in list, first position = 0, helper for the vforce page
        public Address__c oAd {get;set;}
        public Boolean addNetworkDetails {get;set;}
        public CAddressResult (Address__c oAd, Integer index) {this.oAd = oAd;this.addNetworkDetails = false;this.index=index;}
        public String networkDetailsErrMsg {get;set;}
        public String NINAS_LastUpdate_c_via_ISO {get {if(oAd!=null) return ISOFromDate(oAd.NINAS_LastUpdate__c); else return null;} 
                                                  set {if(oAd!=null) oAd.NINAS_LastUpdate__c = DateFromISO(value);}
                                                 }
                                                 
    }

    //////////////////////
    // global parameter //
    //////////////////////
    private static final Integer numPrecheckedRetrieveNetworkDetails = 2; //how many addresses are immediatly submitted to the retrieveNetworkDetails webservice.
    private static final Integer maxAddresses = 150; //number of address results retrieved at most for a single lookup of addresses (retrieveAddresses)
    
    ///////////////////////
    // actual controller //
    ///////////////////////
    
    //members
    public ApexPages.StandardController ctrl;
    public Address__c curAd {get;set;}
    public Address__c origAd {get;private set;}//read-only for the page
    public List<CAddressResult> cAdResList {get;set;}
    public Integer selectedAdResIndex {get;set;} //selected for copying to the Edit (input and output) fields
    public Integer selectedAdResIndexForNetwDetails {get;set;}
    public Boolean retrieveAddressesIsFresh {get;set;} //if true, means that the retrieveAddresses result is present and still consistent with what is in the Edit (input) fields
    private Map<String, Cable_Company__c> ccMap = HTTPRequestNINAS.getCableCompanyMap();
    public Integer numAdFound {get; private set;}
    
    //constructor
    public AddressCheckInteractive_Controller(ApexPages.StandardController ctrl) {
        this.ctrl = ctrl;
        curAd = (Address__c)ctrl.getRecord();
        origAd = curAd.clone();// no need to clone Id etc, just the plain fields are relevant
        if (curAd == null) curAd = new Address__c(); //doesn't have a real use, except a 'draft check on address entered on the spot' for testing
        cAdResList = new List<CAddressResult>();
        selectedAdResIndex = null; //means no radio button will be checked
        retrieveAddressesIsFresh = false; //means that when Check! is clicked, the retrieveAddresses ws will be called
    }
    
    //methods
    // (support display of changes)
    public Boolean isModified_Street_c              {get {return curAd.Street__c              != origAd.Street__c             ;}}
    public Boolean isModified_House_Number_c        {get {return curAd.House_Number__c        != origAd.House_Number__c       ;}}
    public Boolean isModified_Subnumber_c           {get {return curAd.Subnumber__c           != origAd.Subnumber__c          ;}}
    public Boolean isModified_Box_c                 {get {return curAd.Box__c                 != origAd.Box__c                ;}}
    public Boolean isModified_Floor_c               {get {return curAd.Floor__c               != origAd.Floor__c              ;}}
    public Boolean isModified_Apartment_c           {get {return curAd.Apartment__c           != origAd.Apartment__c          ;}}
    public Boolean isModified_Postal_Code_c         {get {return curAd.Postal_Code__c         != origAd.Postal_Code__c        ;}}
    public Boolean isModified_Place_c               {get {return curAd.Place__c               != origAd.Place__c              ;}}
    public Boolean isModified_CanonicalAddressId_c  {get {return curAd.CanonicalAddressId__c  != origAd.CanonicalAddressId__c ;}}
    public Boolean isModified_StreetId_c            {get {return curAd.StreetId__c            != origAd.StreetId__c           ;}}
    public Boolean isModified_MunicipalityId_c      {get {return curAd.MunicipalityId__c      != origAd.MunicipalityId__c     ;}}
    public Boolean isModified_IsVerified_c          {get {return curAd.IsVerified__c          != origAd.IsVerified__c         ;}}
    public Boolean isModified_IsValidated_c         {get {return curAd.IsValidated__c         != origAd.IsValidated__c        ;}}
    public Boolean isModified_NINAS_SAPId_c         {get {return curAd.NINAS_SAPId__c         != origAd.NINAS_SAPId__c        ;}}
    public Boolean isModified_NINAS_RefNo_c         {get {return curAd.NINAS_RefNo__c         != origAd.NINAS_RefNo__c        ;}}
    public Boolean isModified_NINAS_Node_c          {get {return curAd.NINAS_Node__c          != origAd.NINAS_Node__c         ;}}
    public Boolean isModified_NINAS_CATSAPStatus_c  {get {return curAd.NINAS_CATSAPStatus__c  != origAd.NINAS_CATSAPStatus__c ;}}
    public Boolean isModified_NINAS_Remark_c        {get {return curAd.NINAS_Remark__c        != origAd.NINAS_Remark__c       ;}}
    public Boolean isModified_NINAS_CustomerInfo_c  {get {return curAd.NINAS_CustomerInfo__c  != origAd.NINAS_CustomerInfo__c ;}}
    public Boolean isModified_NINAS_CableCompany_c  {get {return curAd.NINAS_CableCompany__c  != origAd.NINAS_CableCompany__c ;}}
    public Boolean isModified_NINAS_LastUpdate_c    {get {return curAd.NINAS_LastUpdate__c    != origAd.NINAS_LastUpdate__c   ;}}

    public Boolean isModified_anyInputField {get {return
           isModified_Street_c
        || isModified_House_Number_c
        || isModified_Subnumber_c
        || isModified_Box_c
        || isModified_Floor_c
        || isModified_Apartment_c
        || isModified_Postal_Code_c
        || isModified_Place_c
        || isModified_CanonicalAddressId_c //to prevent that when isModified_anyInputField and new address info is retrieved, and you remodify into the original data, that the system wouldn't requery the address anymore
        ;
        }}

    public void overwrite (Address__c adToOverwrite, Address__c adOverwriting, Boolean includeAddress, Boolean includeNetworkDetails){
        //kind of clone, but that keeps the original object intact, because we don't have the pointer to that object, hence we
        //cannot have it point to a cloned object (it is incorporated in the standardController, and we can only do getRecord(), not setRecord())
        
        //(Id is never overwritten)
        if (includeAddress){
            adToOverwrite.Street__c              = adOverwriting.Street__c             ;
            adToOverwrite.House_Number__c        = adOverwriting.House_Number__c       ;
            adToOverwrite.Subnumber__c           = adOverwriting.Subnumber__c          ;
            adToOverwrite.Box__c                 = adOverwriting.Box__c                ;
            adToOverwrite.Floor__c               = adOverwriting.Floor__c              ;
            adToOverwrite.Apartment__c           = adOverwriting.Apartment__c          ;
            adToOverwrite.Postal_Code__c         = adOverwriting.Postal_Code__c        ;
            adToOverwrite.Place__c               = adOverwriting.Place__c              ;
            adToOverwrite.CanonicalAddressId__c  = adOverwriting.CanonicalAddressId__c ;
            adToOverwrite.StreetId__c            = adOverwriting.StreetId__c           ;
            adToOverwrite.MunicipalityId__c      = adOverwriting.MunicipalityId__c     ;
            adToOverwrite.IsVerified__c          = adOverwriting.IsVerified__c         ;
            adToOverwrite.IsValidated__c         = adOverwriting.IsValidated__c        ;
        }
        if (includeNetworkDetails) {
            adToOverwrite.NINAS_SAPId__c         = adOverwriting.NINAS_SAPId__c        ;
            adToOverwrite.NINAS_RefNo__c         = adOverwriting.NINAS_RefNo__c        ;
            adToOverwrite.NINAS_Node__c          = adOverwriting.NINAS_Node__c         ;
            adToOverwrite.NINAS_CATSAPStatus__c  = adOverwriting.NINAS_CATSAPStatus__c ;
            adToOverwrite.NINAS_Remark__c        = adOverwriting.NINAS_Remark__c       ;
            adToOverwrite.NINAS_CustomerInfo__c  = adOverwriting.NINAS_CustomerInfo__c ;
            adToOverwrite.NINAS_CableCompany__c  = adOverwriting.NINAS_CableCompany__c ;
            adToOverwrite.NINAS_LastUpdate__c    = adOverwriting.NINAS_LastUpdate__c   ;
        }
    }
    
    public String curAd_NINAS_LastUpdate_c {get {return ISOFromDate(curAd.NINAS_LastUpdate__c);} 
                                            set {curAd.NINAS_LastUpdate__c = DateFromISO(value);}
                                           }
    public String origAd_NINAS_LastUpdate_c {get {return ISOFromDate(origAd.NINAS_LastUpdate__c);} 
                                            set {origAd.NINAS_LastUpdate__c = DateFromISO(value);}
                                           }
 
    //helper function
    public static String ISOFromDate (Date dt){
        if (dt != null) return dt.year()+'-'+('0'+dt.month()).right(2)+'-'+('0'+dt.day()).right(2); 
        else return null;
    }
    public static Date DateFromISO (String s) {
        if (s != null && s.length()==10) {List<String> dpList = s.split('-'); return Date.newInstance(Integer.valueOf(dpList[0]),Integer.valueOf(dpList[1]),Integer.valueOf(dpList[2]));} 
        else return null;
    }
   
    //actions
    public ApexPages.PageReference doCheck(){
        
        //determine if retrieveAddresses must be done
        retrieveAddressesIsFresh = retrieveAddressesIsFresh && ! isModified_anyInputField;
        
        //do a retrieveAddresses when needed
        if ( ! retrieveAddressesIsFresh) {
            List<Address__c> results;
            try{
                DOM.XMLNode bodyNode;
                bodyNode = HTTPRequestNINAS.telenetOsbWScall(
                    HTTPRequestNINAS.getSoapXML_retrieveAddresses (
                        HTTPRequestNINAS.getSoapCore_retrieveAddresses(curAd), maxAddresses));    
                results = HTTPRequestNINAS.parseResponse_retrieveAddresses(bodyNode);
                if (results != null && results.size() == 0) throw new HTTPRequestNINAS.HNINASException('Address Check did not find any matching Addresses');
                //results == null means there was an error which will already have been thrown
            } catch (HTTPRequestNINAS.HNINASException e) {
                ApexPages.addMessages(e);  
            } catch (Exception e) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL, e.getMessage(), e.getStackTraceString()));
            }    
    
            if (results != null && results.size() > 0){ //the only non-erronic case
                cAdResList.clear(); //TODO: do not clear the adRes listitems that have had a retrieveNetworkDetails
                for (Integer i=0; i< results.size(); i++) {
                    Address__c adr = results[i];
                    cAdResList.add(new CAddressResult(adr, i));
                }
                numAdFound = results.size();
                if (results.size() == maxAddresses) 
                    ApexPages.addMessage(new ApexPages.Message(ApexPages.severity.WARNING, 'The number of addresses found equals the maximum ('+maxAddresses+'). Not all results may be visible. Please refine search criteria if the address you are looking for is not there.'));
            } else cAdResList.clear(); //to avoid confusion, old results are erased. 
            
            if (cAdResList.size() == 1) selectedAdResIndex = 0;
            else selectedAdResIndex = null;//necessary because an empty input field on the html page is translated into 0 when bounded to an Integer
            
            retrieveAddressesIsFresh = true;
        }

        //pre-check addresses for retrieveNetworkDetails. 
        //all are checked but only if the total is less than a predetermined number
        if (cAdResList != null && cAdResList.size()<=numPrecheckedRetrieveNetworkDetails) for (CAddressResult cAdRes : cAdResList){
            cAdRes.addNetworkDetails = true;
        }

        //perform retrieveNetworkCheck for those adResList items where it was requested AND not fresh, ie. not yet done (because the only input field,
        //namely CanonicalAddressId, cannot be modified in an adResList item. And 'done' means that the NINAS_SAPId__c is filled OR the networkDetailsErrMsg is filled.
        if (cAdResList != null) for (CAddressResult cAdRes : cAdResList){
            //TODO: only perform max 10 requests (or 9 if retrieveAddresses was done) --> not needed anymore because networkDetails is performed via ajax each time an adRes is checked for retrieving networkDetails.
            doNetworkDetailsCheck(cAdRes.index);
        }

        //already apply result (only in case 1 unambiguous result was found, see a few lines back)
        applyAddressResult();
        

        //stay on the same page after execution of action
        return null;
    }
    
    public ApexPages.PageReference doNetworkDetailsCheck(){
        //for use in ajax
        //uses selectedAdResIndexForNetwDetails to decide what AdRes to run through retrieveNetworkDetails
        doNetworkDetailsCheck(selectedAdResIndexForNetwDetails);
        //if an addressResult was selected, need to apply the networkDetails result to the Edit fields as well
        applyAddressResult();
        return null;//stay on the same page
    }
    
    private void doNetworkDetailsCheck(Integer index){
            CAddressResult cAdRes = cAdResList[index];
            if (String.isBlank(cAdRes.oAd.NINAS_SAPId__c) && String.isBlank(cAdRes.networkDetailsErrMsg) && cAdRes.addNetworkDetails) {
                //perform webservice call
                List<Address__c> resultList;
                try{
                    DOM.XMLNode bodyNode;
                    bodyNode = HTTPRequestNINAS.telenetOsbWScall(
                        HTTPRequestNINAS.getSoapXML_retrieveServiceAccessPoints (
                            HTTPRequestNINAS.getSoapCore_retrieveServiceAccessPoints(cAdRes.oAd)));    
                    resultList = HTTPRequestNINAS.parseResponse_retrieveServiceAccessPoints(bodyNode, ccMap);
                    if (resultList == null || resultList.size()==0) throw new HTTPRequestNINAS.HNINASException('could not retrieve networkDetails'); //will not occur since an error will have been thrown before
                    cAdRes.networkDetailsErrMsg = null;
                } catch (HTTPRequestNINAS.HNINASException e) {
                    if (e.errorCode == 'OUTB_CALL_HTTPSTATUS'){
                        String err = e.getMessage();
                        Integer startRelevantPart = err.indexOfIgnoreCase('Fault is:') + 9 ;
                        if (startRelevantPart <= err.length()) cAdRes.networkDetailsErrMsg = err.substring(startRelevantPart,err.length()).trim();
                        else cAdRes.networkDetailsErrMsg = e.getMessage();
                    } else {
                        cAdRes.networkDetailsErrMsg = e.getMessage();
                    }
                } catch (Exception e) {
                    cAdRes.networkDetailsErrMsg =  e.getMessage() +  e.getStackTraceString();//this should never occur, but you never know. At least you get the error on screen then.
                }    
        
                if (resultList != null && resultList.size()>0){ //the only non-erronic case
                    overwrite (cAdRes.oAd, resultList[0], false, true); // TODO instead of just taking the first of the list, add as many items to cAdResList as needed to accomodate all the returned SAP's, each time duplicating the already present CAdRes.oAd info (particularly the CanonicalAddressId)
                } else {
                    overwrite (cAdRes.oAd, new Address__c(), false, true); //will overwrite the networkDetails fields, but not the error field.
                }
                
            }
    }
    
    public ApexPages.PageReference applyAddressResult(){
        //uses input field selectedAdResIndex to determine which address result to apply to the Edit fields
        if (selectedAdResIndex == null || selectedAdResIndex >= cAdResList.size()) return null;
        if (selectedAdResIndex == -1){
            //restore orig into Edit fields
            overwrite (curAd, origAd, true, true); //Address details and NetworkDetails
        } else {
            //copy data of selected address result into Edit fields. Rules:
            //  - if (succesfully retrieved) networkDetails are present, copy them as well
            //  - if the CanonicalAddressId is modified and no (succesfully retrieved) networkDetails are present,
            //    clear all NetworkDetails of the curAd
            CAddressResult cAdRes = cAdResList[selectedAdResIndex];
            Boolean canonModif = curAd.CanonicalAddressId__c != cAdRes.oAd.CanonicalAddressId__c;
            overwrite (curAd, cAdRes.oAd, true, String.isNotBlank(cAdRes.oAd.NINAS_SAPId__c)); //in any case address details, and if applicable, NetworkDetails
            if (canonModif && String.isBlank(cAdRes.oAd.NINAS_SAPId__c)) overwrite (curAd, new Address__c(), false, true);

        }
        return null;
    }
    
    public ApexPages.PageReference refresh(){
        return null;
    }

}