'use strict';
var __rest = (this && this.__rest) || function (s, e) {
    var t = {};
    for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
        t[p] = s[p];
    if (s != null && typeof Object.getOwnPropertySymbols === "function")
        for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) if (e.indexOf(p[i]) < 0)
            t[p[i]] = s[p[i]];
    return t;
};
Object.defineProperty(exports, "__esModule", { value: true });
const csvParseBase = require("csv-parse");
const transform = require("stream-transform");
const rp = require("request-promise");
const riderUrl = 'http://localhost:8000/rider';
const driverUrl = 'http://localhost:8000/driver';
// const riderUrl = 'https://api.carpoolvote.com/live/rider';
// const driverUrl = 'https://api.carpoolvote.com/live/driver';
const createItem = (row, isRider, orgUuid) => {
    let adjustedItem = Object.assign({}, row);
    // NOTE: node app is based around the form coming from html (rather than a
    // js function) to support the widest range of clients. So it expects a false
    // value to be signified by a property not being present, otherwise the value
    // is true. So any boolean property that is not true is removed.
    const removeFalseProp = (key, rowData) => {
        let newRow = {};
        const _a = key, field = rowData[_a], oneTrip = __rest(rowData, [typeof _a === "symbol" ? _a : _a + ""]);
        console.log('key', field);
        if (field && field.toUpperCase() !== 'TRUE') {
            console.log('true');
            newRow = oneTrip;
        }
        else {
            console.log('false');
            newRow = rowData;
        }
        return newRow;
    };
    if (isRider === true) {
        adjustedItem = removeFalseProp('TwoWayTripNeeded', adjustedItem);
        adjustedItem = removeFalseProp('RiderIsVulnrable', adjustedItem);
        adjustedItem = removeFalseProp('RiderWillNotTalkPolitics', adjustedItem);
        adjustedItem = removeFalseProp('PleaseStayInTouch', adjustedItem);
        adjustedItem = removeFalseProp('NeedWheelchair', adjustedItem);
        adjustedItem = removeFalseProp('RiderLegalConsent', adjustedItem);
        adjustedItem = removeFalseProp('RiderWillBeSafe', adjustedItem);
        adjustedItem.RidingOnBehalfOfOrganization = true;
        adjustedItem.RidingOBOOrganizationName = orgUuid;
        // console.log('rider', adjustedItem);
    }
    else {
        adjustedItem = removeFalseProp('DriverWillTakeCare', adjustedItem);
        adjustedItem = removeFalseProp('DriverCanLoadRiderWithWheelchair', adjustedItem);
        adjustedItem = removeFalseProp('DriverWillNotTalkPolitics', adjustedItem);
        adjustedItem = removeFalseProp('PleaseStayInTouch', adjustedItem);
        adjustedItem = removeFalseProp('RidersCanSeeDriverDetails', adjustedItem);
        adjustedItem = removeFalseProp('DriverWillTakeCare', adjustedItem);
        adjustedItem = removeFalseProp('RiderWillBeSafe', adjustedItem);
        adjustedItem.DrivingOnBehalfOfOrganization = true;
        adjustedItem.DrivingOBOOrganizationName = orgUuid;
        // console.log('driver', adjustedItem);
    }
    return adjustedItem;
};
function uploadCsv(itemsStream, orgUuid, callback) {
    const options = {
        columns: true,
        trim: true,
        skip_lines_with_error: false
    };
    const uploadParseErrorType = 'parse error';
    const uploadDbInputErrorType = 'db input error';
    const items = [];
    const adjustedItems = [];
    let ridersCsv = false; // if false after parsingStarted === true, this is a drivers csv
    let parsingStarted = false;
    let postUrl = '';
    debugger;
    const csvParse = csvParseBase(options);
    const transformer = transform(record => {
        // console.log('rec:', record);
        items.push(record);
        if (parsingStarted === false) {
            if (record.RiderFirstName !== undefined) {
                ridersCsv = true;
                parsingStarted = true;
                postUrl = riderUrl;
            }
            else if (record.DriverFirstName !== undefined) {
                parsingStarted = true;
                postUrl = driverUrl;
            }
        }
        const newRecord = createItem(record, ridersCsv, orgUuid);
        adjustedItems.push(newRecord);
        return newRecord;
    });
    itemsStream.pipe(csvParse).pipe(transformer);
    csvParse.on('error', function (err) {
        debugger;
        return callback({ error: err.message, type: uploadParseErrorType });
    });
    csvParse.on('end', async function () {
        // console.log('new items:', adjustedItems);
        const rows = adjustedItems;
        const rowsAddedToDb = [];
        const inputErrors = [];
        const addRowToDb = async (postUrl, row, callback) => {
            // console.log(row);
            const postOptions = {
                method: 'POST',
                url: postUrl,
                rejectUnauthorized: false,
                form: row
            };
            try {
                const response = await rp.post(postOptions);
                debugger;
                const resp = JSON.parse(response);
                return resp;
            }
            catch (error) {
                debugger;
                console.log('error', error);
                const inputErr = {
                    error: error.message,
                    type: uploadDbInputErrorType,
                    data: error.options.form
                };
                inputErrors.push(inputErr);
                return inputErr;
            }
        };
        for (const row of rows) {
            const resp = await addRowToDb(postUrl, row, callback);
            debugger;
            const inputtedItem = resp;
            // console.log(inputtedItem);
            if (inputtedItem.error === undefined) {
                debugger;
                rowsAddedToDb.push(inputtedItem);
            }
        }
        debugger;
        // console.log('rows done:', rowsAddedToDb);
        console.log('rows added count :', rowsAddedToDb.length);
        const replyDetailsLength = {
            recordsReceived: rows.length,
            uploadCount: rowsAddedToDb.length
        };
        const errorOccurred = inputErrors.length > 0;
        const replyDetailsFull = errorOccurred
            ? {
                replyDetailsLength,
                inputErrorsCount: inputErrors.length,
                inputErrors
            }
            : replyDetailsLength;
        if (errorOccurred) {
            return callback(replyDetailsFull);
        }
        else {
            debugger;
            return callback(null, replyDetailsFull);
        }
    });
}
function uploadRidersOrDrivers(fileData, orgUuid, callback) {
    uploadCsv(fileData, orgUuid, function (err, httpResponse) {
        if (err) {
            return callback(err);
        }
        debugger;
        callback(null, httpResponse);
    });
}
exports.uploadRidersOrDrivers = uploadRidersOrDrivers;
//# sourceMappingURL=csvImport.js.map