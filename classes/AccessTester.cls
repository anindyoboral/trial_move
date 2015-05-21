public with sharing class AccessTester {

    //Author        :   Jan Selis, Synergy2core BVBA
    //Company       :   4C Consulting, Stationsstraat 60 2800 Mechelen +32 15 281 281
    //Created       :   nov 2013 as an aid to the ordering form
    //Description   :   This class allows to programmatically test readability or writeability for a certain logged on user as it would be through 
    //                  standard page layouts.

    public static Boolean testReadable(Id theId){
        String typeName = theId.getSObjectType().getDescribe().getName();
        String secondField = 'Name';
        if (typeName=='Case' || typeName=='Task' || typeName=='Event') secondField = 'Subject';
        String qry = 'Select Id, '+secondField+' from '+typeName+' where Id = \''+theId+'\'';
        List<SObject> sObjList = Database.query(qry);
        return sObjList.size()>0;
    }

    public static Boolean testWriteable(Id theId){
        String typeName = theId.getSObjectType().getDescribe().getName();
        String secondField = 'Name';
        if (typeName=='Case' || typeName=='Task' || typeName=='Event') secondField = 'Subject';
        Schema.SObjectType oTp = Schema.getGlobalDescribe().get(typeName);
        SObject obj = oTp.newSObject();
        obj.put('Id', theId);
        obj.put(secondField, 'xyz');
        

        Boolean writeable = true;
        System.savePoint sp = Database.setSavePoint();
        Database.SaveResult sr = Database.update(obj, false);
        for (Database.Error dErr : sr.getErrors()) {
            String err = dErr.getMessage();
            System.debug('********accessTester errmsg:'+err);
            writeable = false;
        }
        Database.rollback(sp);

        return writeable;
    }

}