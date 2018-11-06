export { PostFunctions, PayloadFunc2 };

import { DbQueriesPosts } from "./DbQueriesPosts"
import { PostgresQueries }  from "./postgresQueries";
import { RouteNamesAddDriverRider } from "./RouteNames";

let dbQueriesPosts = new DbQueriesPosts();
let routeNamesAddDriverRider = new RouteNamesAddDriverRider();
let postgresQueries = new PostgresQueries();

// const dbQueries       = require('./dbQueries.js');

interface PayloadFunc {
  (self:PostFunctions, req: any, payload: any): any[]
}

interface PayloadFunc2 {
  (req: any, payload: any): any[]
}

interface LogPostFunc {
  (self: PostFunctions, req: any)
}

interface GetSubmitStringFunc {
  (): string
}

class PostFunctions {

  private rfPool: any = undefined;

  getExecResultStrings: any = undefined;  

  postRider: any = undefined;
  postHelper: any = undefined;
  postDriver: any = undefined;
  postUser: any = undefined;

  setPool (pool: any) {
    this.rfPool = pool;

    this.postDriver = 
      this.createPostFn 
      (routeNamesAddDriverRider.DRIVER_ROUTE, 
        dbQueriesPosts.dbGetSubmitDriverString, 
        this.createPayloadFn(this.getDriverPayloadAsArray), 
        this.logPostDriver);

    this.postHelper = 
      this.createPostFn 
      (routeNamesAddDriverRider.HELPER_ROUTE, 
        dbQueriesPosts.dbGetSubmitHelperString, 
        this.createPayloadFn(this.getHelperPayloadAsArray), 
        this.logPostHelper);

    this.postRider = 
      this.createPostFn 
      (routeNamesAddDriverRider.RIDER_ROUTE, 
        dbQueriesPosts.dbGetSubmitRiderString, 
        this.createPayloadFn(this.getRiderPayloadAsArray), 
        this.logPostRider);

    this.postUser = 
      this.createPostFn 
      (routeNamesAddDriverRider.USER_ROUTE, 
        dbQueriesPosts.dbGetSubmitUserString, 
        this.createPayloadFn(this.getUserPayloadAsArray), 
        this.logPostUser);
    }

  logPost (req: any) {
    // req.log();
  }

  constructor () {
    this.getExecResultStrings = this.createResultStringFn(' fn called: ', ' fn call failed: '); 
  }

  createResultStringFn (successText: string, failureText: string) {

    function getResultStrings (tableName: string) {
      var resultStrings = {
        success: ' xxx ' + successText,
        failure: ' ' + failureText 
      }

      resultStrings.success = tableName + resultStrings.success; 
      resultStrings.failure = tableName + resultStrings.failure; 

      return resultStrings;
    }

    return getResultStrings;
  }

  createPostFn(
    resultStringText: string,
    dbQueryFn: GetSubmitStringFunc,
    payloadFn: PayloadFunc2,
    logFn: LogPostFunc
  ) {
    var self = this;

    function postFn(req: any, reply: any) {
      var payload = req.payload;
      var results = self.getExecResultStrings(resultStringText);

      if (logFn !== undefined) {
        logFn(self, req);
      } else {
        self.logPost(req);
      }

      postgresQueries.dbExecuteCarpoolAPIFunction_Insert(
        payload,
        self.rfPool,
        dbQueryFn,
        payloadFn,
        req,
        reply,
        results
      );
    }

    return postFn;
  }

  createPayloadFn(payloadFn: PayloadFunc) {
    var self = this;

    function callPayloadFn(req: any, payload: any) {
      return payloadFn(self, req, payload);
    }

    return callPayloadFn;
  }

  getDriverPayloadAsArray(self: PostFunctions, req: any, payload: any): any[] {
    var ip = self.getClientAddress(req);
    return [
      ip,
      payload.DriverCollectionZIP,
      payload.DriverCollectionRadius,
      payload.AvailableDriveTimesJSON,
      payload.DriverCanLoadRiderWithWheelchair ? 'true' : 'false',
      payload.SeatCount,
      payload.DriverLicenceNumber,
      payload.DriverFirstName,
      payload.DriverLastName,
      payload.DriverEmail,
      payload.DriverPhone,
      payload.DrivingOnBehalfOfOrganization ? 'true' : 'false',
      payload.DrivingOBOOrganizationName,
      payload.RidersCanSeeDriverDetails ? 'true' : 'false',
      payload.DriverWillNotTalkPolitics ? 'true' : 'false',
      payload.PleaseStayInTouch ? 'true' : 'false',
      payload.DriverPreferredContact
        ? payload.DriverPreferredContact.toString()
        : 'Email,Phone,SMS',
      payload.DriverWillTakeCare ? 'true' : 'false'
    ];
  }

  getHelperPayloadAsArray(self: PostFunctions, req: any, payload: any): any[] {
    return [
      payload.Name,
      payload.Email,
      payload.Capability
      // 1, moment().toISOString()
    ];
  }

  getRiderPayloadAsArray(self: PostFunctions, req: any, payload: any): any[] {
    var ip = self.getClientAddress(req);

    const payloadAsArray = [
      ip,
      payload.RiderFirstName,
      payload.RiderLastName,
      payload.RiderEmail,
      payload.RiderPhone,
      payload.RiderCollectionZIP,
      payload.RiderDropOffZIP,
      payload.AvailableRideTimesJSON,
      payload.TotalPartySize,
      payload.TwoWayTripNeeded ? 'true' : 'false',
      payload.RiderIsVulnrable ? 'true' : 'false',
      payload.RiderWillNotTalkPolitics ? 'true' : 'false',
      payload.PleaseStayInTouch ? 'true' : 'false',
      payload.NeedWheelchair ? 'true' : 'false',
      payload.RiderPreferredContact
        ? payload.RiderPreferredContact.toString()
        : 'Email,Phone,SMS',
      payload.RiderAccommodationNotes,
      payload.RiderLegalConsent ? 'true' : 'false',
      payload.RiderWillBeSafe ? 'true' : 'false',
      payload.RiderCollectionAddress,
      payload.RiderDestinationAddress,
      payload.RidingOnBehalfOfOrganization ? 'true' : 'false',
      payload.RidingOBOOrganizationName
    ]; // this one should be in local time as passed along by the forms

    return payloadAsArray;
  }

  getUserPayloadAsArray(self: PostFunctions, req: any, payload: any): any[] {
    var ip = self.getClientAddress(req);
    return [
      ip,
      payload.email,
      payload.username,
      payload.password,
      payload.admin
    ];
  }

  getClientAddress(req: any) {
    // See http://stackoverflow.com/questions/10849687/express-js-how-to-get-remote-client-address
    // and http://stackoverflow.com/questions/19266329/node-js-get-clients-ip/19267284
    return (
      (req.headers['x-forwarded-for'] || '').split(',')[0] ||
      req.connection.remoteAddress
    );
  }

  logPostDriver(self: PostFunctions, req: any) {
    var payload = req.payload;

    console.log('driver radius1 : ' + payload.DriverCollectionRadius);
    self.sanitiseDriver(payload);
    console.log('driver radius2 : ' + payload.DriverCollectionRadius);

    console.log('driver payload: ' + JSON.stringify(payload, null, 4));
    console.log('driver zip: ' + payload.DriverCollectionZIP);

    // req.log();
  }

  logPostHelper(self: PostFunctions, req: any) {
    var payload = req.payload;

    // req.log();

    console.log('helper payload: ' + JSON.stringify(payload, null, 4));
  }

  logPostRider(self: PostFunctions, req: any) {
    var payload = req.payload;

    //console.log("rider state1 : " + payload.RiderVotingState);
    self.sanitiseRider(payload);
    //console.log("rider state2 : " + payload.RiderVotingState);

    // req.log();

    console.log("rider payload: " + JSON.stringify(payload, null, 4));
    console.log("rider zip: " + payload.RiderCollectionZIP);
  }

  logPostUser (self: PostFunctions, req: any) {
    var payload = req.payload;

    // self.sanitiseRider(payload);

    // req.log();

    console.log("user payload: " + JSON.stringify(payload, null, 4));
  }

  sanitiseRider (payload: any) {

    // if (payload.RiderVotingState === undefined) {
    //   payload.RiderVotingState = "MO";
    // }
  }

  sanitiseDriver (payload: any) {
    if (payload.DriverCollectionRadius === undefined ||
        payload.DriverCollectionRadius === "") {
      // console.log("santising...");
      payload.DriverCollectionRadius = 0;
    }    
  }
}
