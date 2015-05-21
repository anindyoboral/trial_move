public class AddressChoice {
    //Author :      Jan Selis, Synergy2core BVBA for 4C Consulting, Stationsstraat 60/5 2800 Mechelen
    //Date :        2013-sept
    //Description:  cooperates with cOrder and its subclasses to define a choice of address

    public class AddressChoiceException extends Exception {} 
    
    //members
    public cOrder.CAddressList cAdrList; //links to the CAddressList object containing data and functionality for chosing between existing addresses
    private cOrder.CAddress cAd; //temp structure to hold the address data of this address choice (for example installation address of a product_order)
    private String adType; //contains type of address: 'INSTALLATION', 'INVOICE', 'COINVOICE', 'ORDERING'
    private String adNEWKey; //one AddressChoice instance can have exactly one address to be newly created in the database. This member contains the unique key to be assigned to it as placeholder for Salesforce Id of the addres
    private AddressChoice refAdrChoice; //link to the AddressChoice object to which current AddressChoice can be made 'equal' ('use same address as ordering address')
    private String key; //contains unique identifier of this AddressChoice, set by constructor
    private String keyReadable; //human readable identification of this address choice
    private ValidationMatrix vm; //// holds reference to the validation matrix used by the page to keep track of validation results

    public AddressChoice(cOrder.CAddressList cAdrList, String adType, String adNEWKey, AddressChoice refAdrChoice, String adChoiceKey, ValidationMatrix vm) {
        this.cAdrList = cAdrList;
        this.adType   = adType;
        //check that adNEWKey doesn't exist yet in cAdrList, because every AddressChoice object should have its own and only one 'new address placeholder'
        if (cAdrList.contains(adNEWKey)) throw new AddressChoiceException('Tried to initialize an AddressChoice \'' + adType + '\' with a NEWKey ('+adNEWKey+') that already existed in the CAddressList reference list. Each AddressChoice should have only one associated NEWKey');
        this.adNEWKey = adNEWKey;
        this.refAdrChoice = refAdrChoice;
        this.cAd = cAdrList.getMain();
        this.key = adChoiceKey;
        this.vm = vm;
        loadValidations(false,null);
        }
    
    //methods
    public void setAddress(String cadKey) {
        cOrder.CAddress cAdFound = cAdrList.get(cadKey); 
        if (cAdFound != null) cAd = cAdFound;
    }
    
    public void removeUnusedNewAddress(){
        if (cAd.key != adNEWKey) cAdrList.remove(adNEWKey);
    }
    
    public void setUsed() {
        cAd.used = true;    
    }

    //actions
    public String createNewAddress(){//returns key of CAddress
        cAdrList.addNew(adNEWKey, 'New '+getAdTypeTxt()+' (will be saved for future use)');
        cAd = cAdrList.get(adNEWKey);
        return adNEWKey;
    }

    
    public void loadValidations(Boolean validate, String locationReadable){
        //if validate = false: just add the reference to the validation in vm
        //if validate = true: validate fields based on order status in vm and type of address
        //results are added to vm
        //keyReadable is only required when validate = true, and is not set during construction because readable value is better generated from overall cOrder level.
        ValidationMatrix.ValidationRule vr;
        
        if (adType == 'INVOICE' || adType == 'COINVOICE'){
            vr = new ValidationMatrix.ValidationRule(key+'INVOICECHK');vm.add(vr);
            if (validate) vr.setResult('eSOF',cAd.getHasCompleteAddressInfo(), 'Invoice Address fields are not complete{locationReadable}: You need at least Street, HouseNr, Zip, Place', locationReadable);
        }
        
        if (adType == 'INSTALLATION'){
            vr = new ValidationMatrix.ValidationRule(key+'INSTALLATIONCONTACTCHK');vm.add(vr);
            if (validate) vr.setResult('eSOF',cAd.getHasCompleteContactInfo(), 'Installation Contact not complete{locationReadable}: You need at least a Name and one way of contacting (email, phone, ...)', locationReadable);

            vr = new ValidationMatrix.ValidationRule(key+'INSTALLATIONPHYSCHK');vm.add(vr);
            if (validate) vr.setResult('eSOF',cAd.getHasCompleteAddressInfo(), 'Installation Address fields are not complete{locationReadable}: You need at least Street, HouseNr, Zip, Place', locationReadable);
        }
            
        //'return' value is the vm reference that was passed into the function

    }
    
    //getters
    public cOrder.CAddress getCAddress(){return cAd;} 
    public List<SelectOption> getCAddressOptions(){return cAdrList.getOptions();} 
    public Boolean getHasNewAddress(){return cAdrList.get(adNEWKey)!=null;} 
    public String getAdType() {return adType;}
    public String getAdTypeTxt(){
        if (adType=='INSTALLATION') return 'Installation Address/Contact';
        if (adType=='INVOICE') return 'Invoice Contact Point';
        if (adType=='COINVOICE') return 'Package Invoice Address';
        if (adType=='ORDERING') return 'Ordering Entity';
        return adType;
    }
    public String getKey() {return key;}
    public ValidationMatrix getVM() {return vm;}
    
    //getters and setters for use in visualforce page, so actually page controller logic
    //selection basics:
    private String    selectedCadKey;               //contains key (either the Id of the Address__c if it already exists in the database, or a temp key to identify it in memory
    public String  getSelectedCadKey()              {return getCAddress().key;}
    public void    setSelectedCadKey (String value) {selectedCadKey = value;}
    public void             setAddress()            {setAddress(selectedCadKey);}
    public void             newAddress()            {selectedCadKey = createNewAddress();} //'create new address and link current address to it'
    public Boolean getEnableNewAddress()            {return ! getHasNewAddress();}

    //support for Address idem as Ref Address
    private Boolean  holdAddressVisible                 =false;//if true, will override the equalness between PO installation and ordering address for showing the PO installation address
    private Boolean      addressIdemRef;                //PRIVATE, contains boolean as given in ajax request
    public Boolean    getAddressIdemRef()               {return (! holdAddressVisible) && getCAddress().key == (refAdrChoice==null?null:refAdrChoice.getCAddress().key);}
    public void       setAddressIdemRef (Boolean value) {addressIdemRef = value;}
    public void    toggleAddressIdemRef()               {    if (addressIdemRef){
                                                                holdAddressVisible = false;
                                                                setAddress(refAdrChoice.getSelectedCadKey()); //set cur address to same address as Ref, need to use the getter for ref address here!
                                                            } else holdAddressVisible = true; //make the address fields visible but it is not necessarily another address yet
                                                        }
}