CREATE OR REPLACE FUNCTION carpoolvote.evaluate_match_single_pair(arg_uuid_driver character varying, arg_uuid_rider character varying)
  RETURNS character varying AS
$BODY$
DECLARE

run_now carpoolvote.match_engine_scheduler.need_run_flag%TYPE;

v_start_ts carpoolvote.match_engine_activity_log.start_ts%TYPE;
v_end_ts carpoolvote.match_engine_activity_log.end_ts%TYPE;
v_evaluated_pairs carpoolvote.match_engine_activity_log.evaluated_pairs%TYPE;
v_proposed_count carpoolvote.match_engine_activity_log.proposed_count%TYPE;
v_error_count carpoolvote.match_engine_activity_log.error_count%TYPE;
v_expired_count carpoolvote.match_engine_activity_log.expired_count%TYPE;

b_rider_all_times_expired  boolean := TRUE;
b_rider_validated boolean := TRUE;
b_driver_all_times_expired boolean := TRUE;
b_driver_validated boolean := TRUE;

RADIUS_MAX_ALLOWED integer := 100;

drive_offer_row carpoolvote.driver%ROWTYPE;
ride_request_row carpoolvote.rider%ROWTYPE;
cnt integer;
match_points integer;
time_criteria_points integer;

ride_times_rider text[];
ride_times_driver text[];
driver_time text;
rider_time text;
seconds_diff integer;

start_ride_time timestamp with time zone;
end_ride_time timestamp with time zone;
start_drive_time timestamp with time zone;
end_drive_time timestamp with time zone;
time_now_pst timestamp without time zone;

zip_origin carpoolvote.zip_codes%ROWTYPE;  -- Driver's origin
zip_pickup carpoolvote.zip_codes%ROWTYPE;  -- Rider's pickup
zip_dropoff carpoolvote.zip_codes%ROWTYPE; -- Rider's dropoff

distance_origin_pickup double precision;  -- From driver origin to rider pickup point
distance_origin_dropoff double precision; -- From driver origin to rider drop off point

g_uuid_driver character varying(50);
g_uuid_rider  character varying(50);
g_record record;
g_email_body text;
g_sms_body text;

BEGIN

	run_now := true;
	--BEGIN
	--	INSERT INTO carpoolvote.match_engine_scheduler VALUES(true);
	--EXCEPTION WHEN OTHERS
	--THEN
		-- ignore
	--END;
	--SELECT need_run_flag INTO run_now from carpoolvote.match_engine_scheduler LIMIT 1;
	IF run_now
	THEN

		
	
		-- Initialize Counters
		v_start_ts := now();
		v_evaluated_pairs := 0;
		v_proposed_count := 0;
		v_error_count := 0;
		v_expired_count := 0;

		
		
		FOR ride_request_row in SELECT * from carpoolvote.rider r
			WHERE r.state in ('Pending','MatchProposed') AND r."UUID" like arg_uuid_rider || '%'
		LOOP
		
			IF length(ride_request_row."AvailableRideTimesUTC") = 0
			THEN
				UPDATE carpoolvote.rider 
				SET state='Failed', state_info='Invalid AvailableRideTimes'
				WHERE "UUID"=ride_request_row."UUID";
				
				b_rider_validated := FALSE;
			END IF;
			

			BEGIN
				-- DriverCollectionZIP
				-- DriverCollectionRadius
			
				SELECT * INTO zip_pickup FROM carpoolvote.zip_codes WHERE zip=ride_request_row."RiderCollectionZIP";
				SELECT * INTO zip_dropoff FROM carpoolvote.zip_codes WHERE zip=ride_request_row."RiderDropOffZIP";
			
			EXCEPTION WHEN OTHERS
			THEN
				UPDATE carpoolvote.rider 
				SET state='Failed', state_info='Unknown/Invalid RiderCollectionZIP or RiderDropOffZIP'
				WHERE "UUID"=ride_request_row."UUID";
				
				b_rider_validated := FALSE;
			END;
			
			IF ride_request_row."TotalPartySize" = 0
			THEN
				UPDATE carpoolvote.rider 
				SET state='Failed', state_info='Invalid TotalPartySize'
				WHERE "UUID"=ride_request_row."UUID";
				
				b_rider_validated := FALSE;
			END IF;
	
	
			-- split AvailableRideTimesUTC in individual time intervals
			ride_times_rider := string_to_array(ride_request_row."AvailableRideTimesUTC", '|');
			b_rider_all_times_expired := TRUE;  -- Assumes all expired
			FOREACH rider_time IN ARRAY ride_times_rider
			LOOP
				BEGIN
					-- each time interval is in ISO8601 format
					-- 2016-10-23T10:00:00-0500/2016-10-23T11:00:00-0500
					start_ride_time := substr(rider_time, 1, 24)::timestamp with time zone;
					end_ride_time := substr(rider_time, 26, 24)::timestamp with time zone;
					
					IF start_ride_time > end_ride_time
					THEN
						UPDATE carpoolvote.rider 
						SET state='Failed', state_info='Invalid value in AvailableRideTimes:' || rider_time
						WHERE "UUID"=ride_request_row."UUID";
				
						b_rider_validated := FALSE;
					ELSE
					
						IF end_ride_time > now()   ----   --[NOW]--[S]--[E]   : not expired
						THEN                       ----   --[S]---[NOW]--[E]  : not expired
													      --[S]--[E]----[NOW] : expired
							b_rider_all_times_expired := FALSE;
						END IF;
					END IF;
				EXCEPTION WHEN OTHERS
				THEN				
					UPDATE carpoolvote.rider
					SET state='Failed', state_info='Invalid value in AvailableRideTimes:' || rider_time
					WHERE "UUID"=ride_request_row."UUID";

					b_rider_validated := FALSE;
				END;
				
				IF b_rider_all_times_expired
				THEN
					UPDATE carpoolvote.rider r
					SET state='Expired', state_info='All AvailableRideTimes are expired'
					WHERE "UUID"=ride_request_row."UUID";

					v_expired_count := v_expired_count +1;
					
					b_rider_validated := FALSE;
				END IF;
				
			END LOOP;
	
			IF b_rider_validated
			THEN
			
 				FOR drive_offer_row in SELECT * from carpoolvote.driver d
 					WHERE state IN ('Pending','MatchProposed','MatchConfirmed')
 					AND ((ride_request_row."NeedWheelchair"=true AND d."DriverCanLoadRiderWithWheelchair" = true) -- driver must be able to transport wheelchair if rider needs it
 						OR ride_request_row."NeedWheelchair"=false)   -- but a driver equipped for wheelchair may drive someone who does not need one
 					AND ride_request_row."TotalPartySize" <= d."SeatCount"  -- driver must be able to accommodate the entire party in one ride

 				LOOP
 
 					IF length(drive_offer_row."AvailableDriveTimesUTC") = 0
 					THEN
 						UPDATE carpoolvote.driver 
 						SET state='Failed', state_info='Invalid AvailableDriveTimes'
 						WHERE "UUID"=drive_offer_row."UUID";
 				
 						b_driver_validated := false;
 					END IF;
 
 					BEGIN
 						SELECT * INTO zip_origin FROM carpoolvote.zip_codes WHERE zip=drive_offer_row."DriverCollectionZIP";
 					EXCEPTION WHEN OTHERS
 					THEN
 						UPDATE carpoolvote.driver 
 						SET state='Failed', state_info='Invalid DriverCollectionZIP'
 						WHERE "UUID"=drive_offer_row."UUID";
 					
 						b_driver_validated := FALSE;
 					END;
 					
 					
 					-- split AvailableDriveTimesUTC in individual time intervals
 					-- NOTE : we do not want actual JSON here...
 					-- FORMAT should be like this 
 					-- 2016-10-01T08:00:00-0500/2016-10-01T10:00:00-0500|2016-10-01T10:00:00-0500/2016-10-01T22:00:00-0500|2016-10-01T22:00:00-0500/2016-10-01T23:00:00-0500
 					ride_times_driver := string_to_array(drive_offer_row."AvailableDriveTimesUTC", '|');
					b_driver_all_times_expired := TRUE;
 					FOREACH driver_time IN ARRAY ride_times_driver
					LOOP
						BEGIN
							-- each time interval is in ISO8601 format
							-- 2016-10-23T10:00:00-0500/2016-10-23T11:00:00-0500
							start_drive_time := substr(driver_time, 1, 24)::timestamp with time zone;
							end_drive_time := substr(driver_time, 26, 24)::timestamp with time zone;
							
							IF start_drive_time > end_drive_time
							THEN
								UPDATE carpoolvote.driver 
								SET state='Failed', state_info='Invalid value in AvailableDriveTimes:' || driver_time
								WHERE "UUID"=drive_offer_row."UUID";
				
								b_driver_validated := FALSE;
							ELSE
								SELECT now() AT TIME ZONE 'PST' into time_now_pst;
							
								IF end_drive_time > time_now_pst   ----   --[NOW]--[S]--[E]   : not expired
								THEN                       ----   --[S]---[NOW]--[E]  : not expired
													      --[S]--[E]----[NOW] : expired
									b_driver_all_times_expired := FALSE;
								END IF;
							END IF;
							
						EXCEPTION WHEN OTHERS
						THEN
							UPDATE carpoolvote.driver 
							SET state='Failed', state_info='Invalid value in AvailableDriveTimes :' || driver_time
							WHERE "UUID"=drive_offer_row."UUID";

							b_driver_validated := FALSE;
						END;
		
		
						IF b_driver_all_times_expired
						THEN
							UPDATE carpoolvote.driver
							SET state='Expired', state_info='All AvailableDriveTimes are expired'
							WHERE "UUID"=drive_offer_row."UUID";

							v_expired_count := v_expired_count +1;
					
							b_driver_validated := FALSE;
						END IF;
				
					END LOOP;		
					IF 	b_driver_validated
					THEN
				
						match_points := 0;
				
						-- Compare RiderCollectionZIP with DriverCollectionZIP / DriverCollectionRadius
						distance_origin_pickup := carpoolvote.distance(
									zip_origin.latitude_numeric,
									zip_origin.longitude_numeric,
									zip_pickup.latitude_numeric,
									zip_pickup.longitude_numeric);
						
						distance_origin_dropoff := carpoolvote.distance(
									zip_origin.latitude_numeric,
									zip_origin.longitude_numeric,
									zip_dropoff.latitude_numeric,
									zip_dropoff.longitude_numeric);

						RAISE NOTICE 'distance_origin_pickup=%', distance_origin_pickup;
						RAISE NOTICE 'distance_origin_dropoff=%', distance_origin_pickup;
						
						IF distance_origin_pickup < RADIUS_MAX_ALLOWED AND distance_origin_dropoff < RADIUS_MAX_ALLOWED
						THEN

							-- driver/rider distance ranking
							IF distance_origin_pickup <= drive_offer_row."DriverCollectionRadius" 
								AND distance_origin_dropoff <= drive_offer_row."DriverCollectionRadius"
							THEN
								match_points := match_points + 200 
									- distance_origin_pickup -- closest distance gets more points 
									- distance_origin_dropoff ;
							END IF; 
							
							RAISE NOTICE 'D-%, R-%, distance ranking Score=%', 
										drive_offer_row."UUID", 
										ride_request_row."UUID", 
										match_points;
			
							
							-- vulnerable rider matching
							IF ride_request_row."RiderIsVulnerable" = false
							THEN
								match_points := match_points + 200;
							ELSIF ride_request_row."RiderIsVulnerable" = true 
								AND drive_offer_row."DrivingOnBehalfOfOrganization" 
							THEN
								match_points := match_points + 200;
							END IF;
					
							RAISE NOTICE 'D-%, R-%, vulnerable ranking Score=%', 
										drive_offer_row."UUID", 
										ride_request_row."UUID", 
										match_points;
			
							-- time matching
							-- Each combination of rider time and driver time can give a potential match
							FOREACH driver_time IN ARRAY ride_times_driver
							LOOP
								FOREACH rider_time IN ARRAY ride_times_rider
								LOOP
									
									v_evaluated_pairs := v_evaluated_pairs +1;
									
									-- each time interval is in ISO8601 format
									-- 2016-10-23T10:00:00-0500/2016-10-23T11:00:00-0500
									start_ride_time := substr(rider_time, 1, 24)::timestamp with time zone;
									end_ride_time := substr(rider_time, 26, 24)::timestamp with time zone;
									
									-- each time interval is in ISO8601 format
									-- 2016-10-23T10:00:00-0500/2016-10-23T11:00:00-0500
									start_drive_time := substr(driver_time, 1, 24)::timestamp with time zone;
									end_drive_time := substr(driver_time, 26, 24)::timestamp with time zone;
									
									
									time_criteria_points := 200;
									
									IF end_drive_time < start_ride_time       -- [ddddd]  [rrrrrr]
										OR end_ride_time < start_drive_time   -- [rrrrr]  [dddddd]
									THEN
										-- we're totally disconnected
										
										IF end_drive_time < start_ride_time
										THEN
										
											-- substracts one point per minute the driver is outside the rider interval
											time_criteria_points := 
												time_criteria_points - abs(EXTRACT(EPOCH FROM (start_ride_time - end_drive_time))) / 60;
										ELSIF end_ride_time < start_drive_time
										THEN
											time_criteria_points := 
												time_criteria_points - abs(EXTRACT(EPOCH FROM (start_drive_time - end_ride_time))) / 60;
										END IF;
										
										if time_criteria_points < 0
										THEN
											time_criteria_points := 0; 
										END IF;
										
									-- ELSIF start_drive_time < start_ride_time  -- [ddd[rdrdrdrdrd]ddd] 
										-- AND end_drive_time > end_ride_time
									-- THEN
										-- -- perfect! we're in the interval
									-- ELSIF start_drive_time < start_ride_time  -- [ddddddd[rdrdrd]rrrr]
										-- AND start_ride_time < end_drive_time
									-- THEN
										-- -- We're at least partially in the interval
									-- ELSIF  start_ride_time < start_drive_time -- [rrrrr[rdrdrd]ddddd]
										-- AND start_drive_time < end_ride_time
									-- THEN
										-- -- We're at least partially in the interval
									-- ELSIF start_ride_time < start_drive_time  -- [rrr[rdrdrdrdrd]rrrrr]
										-- AND end_drive_time < end_ride_time
									-- THEN
										-- -- We're completely in the interval
									END IF;
									
									RAISE NOTICE 'D-%, R-%, final ranking Score=%', 
									drive_offer_row."UUID", 
									ride_request_row."UUID", 
									match_points+time_criteria_points;
									
									IF match_points + time_criteria_points >= 300
									THEN
									
										BEGIN

											
											-- The state of the ride request is 
											
											UPDATE carpoolvote.rider r
											SET state='MatchProposed'
											WHERE r."UUID" = ride_request_row."UUID";

											-- If already MatchConfirmed, keep it as is
											IF drive_offer_row.state = 'Pending'
											THEN
												UPDATE carpoolvote.driver d
												SET state='MatchProposed'
												WHERE d."UUID" = drive_offer_row."UUID";
											END IF;
											
											v_proposed_count := v_proposed_count +1;
											
											RAISE NOTICE 'Proposed Match, Rider=%, Driver=%, Score=%',
														 ride_request_row."UUID", drive_offer_row."UUID", match_points + time_criteria_points;
										EXCEPTION WHEN unique_violation
										THEN
											-- ignore
											-- don't insert duplicate match
										END;                 
									 
									END IF;
									
								END LOOP;
							
								
							END LOOP;

						END IF; -- distances are within radius tolerance
					ELSE
						v_error_count := v_error_count +1;
					END IF; -- driver is validated
 				END LOOP; -- for each drive offer
			ELSE
				v_error_count := v_error_count +1;
			END IF; -- rider is validated
			
		END LOOP; -- for each ride request
		

		
		--v_end_ts := now();
		-- Update activity log
		--INSERT INTO carpoolvote.match_engine_activity_log (
				--start_ts, end_ts , evaluated_pairs,
				--proposed_count, error_count, expired_count)
		--VALUES(v_start_ts, v_end_ts, v_evaluated_pairs,
				--v_proposed_count, v_error_count, v_expired_count);
		
		-- Update scheduler
		-- UPDATE carpoolvote.match_engine_scheduler set need_run_flag = false;
		
		
		
	END IF;
	
	return '';
END
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION carpoolvote.evaluate_match_single_pair(character varying, character varying)
  OWNER TO carpool_admins;
GRANT EXECUTE ON FUNCTION carpoolvote.evaluate_match_single_pair(character varying, character varying) TO carpool_role;



--
-- Name: evaluate_match_single_pair(character varying, character varying); Type: ACL; Schema: carpoolvote; Owner: carpool_admins
--

REVOKE ALL ON FUNCTION evaluate_match_single_pair(arg_uuid_driver character varying, arg_uuid_rider character varying) FROM PUBLIC;
REVOKE ALL ON FUNCTION evaluate_match_single_pair(arg_uuid_driver character varying, arg_uuid_rider character varying) FROM carpool_admins;
GRANT ALL ON FUNCTION evaluate_match_single_pair(arg_uuid_driver character varying, arg_uuid_rider character varying) TO carpool_admins;
GRANT ALL ON FUNCTION evaluate_match_single_pair(arg_uuid_driver character varying, arg_uuid_rider character varying) TO PUBLIC;
GRANT ALL ON FUNCTION evaluate_match_single_pair(arg_uuid_driver character varying, arg_uuid_rider character varying) TO carpool_role;

