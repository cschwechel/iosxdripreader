package services
{
	import com.distriqt.extension.dialog.Dialog;
	import com.distriqt.extension.dialog.DialogView;
	import com.distriqt.extension.dialog.builders.AlertBuilder;
	import com.distriqt.extension.dialog.events.DialogViewEvent;
	import com.distriqt.extension.dialog.objects.DialogAction;
	import com.distriqt.extension.notifications.NotificationRepeatInterval;
	import com.distriqt.extension.notifications.Notifications;
	import com.distriqt.extension.notifications.builders.NotificationBuilder;
	import com.distriqt.extension.notifications.events.NotificationEvent;
	
	import flash.events.EventDispatcher;
	import flash.events.TimerEvent;
	import flash.utils.Timer;
	
	import Utilities.Trace;
	
	import databaseclasses.BgReading;
	import databaseclasses.Calibration;
	import databaseclasses.CalibrationRequest;
	
	import events.CalibrationServiceEvent;
	import events.NotificationServiceEvent;
	import events.TransmitterServiceEvent;
	
	import model.ModelLocator;
	
	/**
	 * listens for bgreadings, at each bgreading user is asked to enter bg value<br>
	 * after two bgreadings, calibration.initialcalibration will be called and then this service will stop. 
	 */
	public class CalibrationService extends EventDispatcher
	{
		[ResourceBundle("calibrationservice")]
		[ResourceBundle("general")]
		
		private static var _instance:CalibrationService = new CalibrationService();
		private static var bgLevel1:Number;
		private static var timeStampOfFirstBgLevel:Number;
		private static var timerForWaitCalibration:Timer;
		
		private static const MAXIMUM_WAIT_FOR_CALIBRATION_IN_SECONDS:int = 60;
		
		
		public static function get instance():CalibrationService {
			return _instance;
		}
		
		public function CalibrationService() {
			if (_instance != null) {
				throw new Error("CalibrationService class constructor can not be used");	
			}
		}
		
		public static function init():void {
			//NOTE THAT THIS FUNCTION CAN BE CALLED MULTIPLE TIMES
			//once at start up of a new sensor, see Sensor.startSensor()
			//then again called when initial calibration is finished, from CalibrationService.as
			if (Calibration.allForSensor().length < 2) {
				//initial calibration still to be done
				bgLevel1 = Number.NaN;
				timeStampOfFirstBgLevel = new Number(0);
				TransmitterService.instance.addEventListener(TransmitterServiceEvent.BGREADING_EVENT, transmitterServiceBGReadingEventReceivedInitialCalibration);
				NotificationService.instance.addEventListener(NotificationServiceEvent.NOTIFICATION_EVENT, notificationReceived);
			} else {
			}
		}
		
		private static function notificationReceived(event:NotificationServiceEvent):void {
			if (event != null) {//not sure why checking, this would mean NotificationService received a null object, shouldn't happen
				var notificationEvent:NotificationEvent = event.data as NotificationEvent;
				if (notificationEvent.id == NotificationService.ID_FOR_EXTRA_CALIBRATION_REQUEST) {
					//double check if it's still needed - in the Android version this double check is not done
					if (!CalibrationRequest.shouldRequestCalibration(ModelLocator.bgReadings.getItemAt(ModelLocator.bgReadings.length - 1) as BgReading)) {
						var alert:DialogView = Dialog.service.create(
							new AlertBuilder()
							.setTitle(ModelLocator.resourceManagerInstance.getString("calibrationservice","calibration_request_title"))
							.setMessage(ModelLocator.resourceManagerInstance.getString("calibrationservice","extra_calibration_not_needed_anymore"))
							.addOption("Ok", DialogAction.STYLE_POSITIVE, 0)
							.build()
						);
						DialogService.addDialog(alert, 30);
					} else {
						calibrationOnRequest(false);
					}
				} else if (notificationEvent.id == NotificationService.ID_FOR_REQUEST_CALIBRATION) {
					//we don't need to do anything with the bgreading, but we need to ask the user for a calibration
					if (((new Date()).valueOf() - timeStampOfFirstBgLevel) > (7 * 60 * 1000 + 100)) { //previous measurement was more than 7 minutes ago , restart
						timeStampOfFirstBgLevel = new Number(0);
						bgLevel1 = Number.NaN;
					}
					//create alert to get the user's input
					var alert:DialogView = Dialog.service.create(
						new AlertBuilder()
						.setTitle(isNaN(bgLevel1) ? ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_first_calibration_title") : ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_second_calibration_title"))
						.setMessage(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration"))
						.addTextField("","Level")
						.addOption("Ok", DialogAction.STYLE_POSITIVE, 0)
						.addOption(ModelLocator.resourceManagerInstance.getString("general","cancel"), DialogAction.STYLE_CANCEL, 1)
						.build()
					);
					alert.addEventListener(DialogViewEvent.CLOSED, intialCalibrationValueEntered);
					alert.addEventListener(DialogViewEvent.CANCELLED, cancellation);
					//setting maximum wait which means in fact user will have two times this period to calibrate
					//because also the notification remains 60 seconds
					DialogService.addDialog(alert, MAXIMUM_WAIT_FOR_CALIBRATION_IN_SECONDS);
				}
			}
		}
		
		public static function stop():void {
		}
		
		private static function transmitterServiceBGReadingEventReceivedInitialCalibration(be:TransmitterServiceEvent):void {
			//if there's already more than two calibrations, then there's no need anymore to request initial calibration
			//same if sensor not active, then length will be 0
			if (Calibration.allForSensor().length < 2) {

				//because the timer based function timerForWaitCalibration doesn't always work as expected
				NotificationService.updateAllNotifications(null);

				//launch a notifcation but wait maximum MAXIMUM_WAIT_FOR_CALIBRATION_IN_SECONDS
				if (timerForWaitCalibration != null) {
					if (timerForWaitCalibration.running) {
						timerForWaitCalibration.stop();					
					}
				}
				timerForWaitCalibration = new Timer(MAXIMUM_WAIT_FOR_CALIBRATION_IN_SECONDS * 1000, 1);
				timerForWaitCalibration.addEventListener(TimerEvent.TIMER, removeInitialCalibrationRequestNotification);
				timerForWaitCalibration.start();
				
				//launch a notification
				//don't do it via the notificationservice, this could result in the notification being cleared but not recreated (NotificationService.updateAllNotifications)
				//the notification doesn't need to open any action, the dialog is already there
				//Only do this if be!= null, because if be == null, then it means this function was called after having entered an invalid number in the dialog, so user is using the app, no need for a dialog
				if (be != null) {
					Notifications.service.notify(
						new NotificationBuilder()
						.setId(NotificationService.ID_FOR_REQUEST_CALIBRATION)
						.setAlert(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration_title"))
						.setTitle(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration_title"))
						.enableVibration(true)
						.enableLights(true)
						.build());
				}
				
			}
			
		}
		
		private static function removeInitialCalibrationRequestNotification (event:TimerEvent):void {
			//user didn't give input on time, dialog is closed by DialogService
			//but also notification needs to be removed, call to update will remove this notification
			trace("in removeInitialCalibrationRequestNotification");
			NotificationService.updateAllNotifications(null);
		}
		
		private static function cancellation(event:DialogViewEvent):void {
		}
		
		private static function intialCalibrationValueEntered(event:DialogViewEvent):void {
			if (event.index == 1) {
				return;
			}
			
			//this will force clear of calibration request notification, if it exists
			NotificationService.updateAllNotifications(null);
			
			var asNumber:Number = new Number(event.values[0] as String);
			if (isNaN(asNumber)) {
				//add the warning message
				var alert:DialogView = Dialog.service.create(
					new AlertBuilder()
					.setTitle(isNaN(bgLevel1) ? ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_first_calibration_title") : ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_second_calibration_title"))
					.setMessage(ModelLocator.resourceManagerInstance.getString("calibrationservice","value_should_be_numeric"))
					.addOption("Ok", DialogAction.STYLE_POSITIVE, 0)
					.build()
				);
				DialogService.addDialog(alert);
				//and ask again a value
				transmitterServiceBGReadingEventReceivedInitialCalibration(null);
			} else {
				if (isNaN(bgLevel1)) {
					bgLevel1 = asNumber;
					timeStampOfFirstBgLevel = (new Date()).valueOf();
				} else {
					Calibration.initialCalibration(bgLevel1, timeStampOfFirstBgLevel, asNumber, (new Date()).valueOf());
					var calibrationServiceEvent:CalibrationServiceEvent = new CalibrationServiceEvent(CalibrationServiceEvent.INITIAL_CALIBRATION_EVENT);
					_instance.dispatchEvent(calibrationServiceEvent);
					init();
				}
			}
		}
		
		/**
		 * will create an alertdialog to ask for a calibration 
		 */
		private static function initialCalibrate():void {
			var alert:DialogView = Dialog.service.create(
				new AlertBuilder()
				.setTitle(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration_title"))
				.setMessage(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration"))
				.addTextField("","Level")
				.addOption("Ok", DialogAction.STYLE_POSITIVE, 0)
				.addOption(ModelLocator.resourceManagerInstance.getString("general","cancel"), DialogAction.STYLE_CANCEL, 1)
				.build()
			);
			alert.addEventListener(DialogViewEvent.CLOSED, calibrationValueEntered);
			alert.addEventListener(DialogViewEvent.CANCELLED, cancellation);
			DialogService.addDialog(alert, 60);
		}
		
		/**
		 * To be used when user clicks the calibrate button<br>
		 * Or when user calibrates as a reaction on a calibration request<br>
		 * In the case of calibration request, there's not going to be an override, for that the parameter override<br>
		 * <br>
		 * if override = true, then a check will be done if there was a calibration in the last 60 minutes and if so the last calibration will be overriden<br>
		 * if override = false, then there's no calibration override, no matter the timing of the last calibration<br>
		 * <br>
		 * if checklast30minutes = true, then it will be checked if there were readings in the last 30 minutes<br>
		 * if checklast30minutes = false, then it will not be checked if there were readings in the last 30 minutes<br>
		 * <br>
		 * For calibration requests, override should 
		 */
		public static function calibrationOnRequest(override:Boolean = true, checklast30minutes:Boolean = true):void {
			//check if there's 2 readings the last 30 minutes
			if (BgReading.last30Minutes().length < 2) {
				var alert:DialogView = Dialog.service.create(
					new AlertBuilder()
					.setTitle(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration_title"))
					.setMessage(ModelLocator.resourceManagerInstance.getString("calibrationservice","can_not_calibrate_right_now"))
					.addOption("Ok", DialogAction.STYLE_POSITIVE, 0)
					.build()
				);
				DialogService.addDialog(alert, 60);
			} else { //check if it's an override calibration
				if (((new Date()).valueOf() - (Calibration.latest(2).getItemAt(0) as Calibration).timestamp < (1000 * 60 * 60)) && override) {
					var alert:DialogView = Dialog.service.create(
						new AlertBuilder()
						.setTitle(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration_title_with_override"))
						.setMessage(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_bg_value_with_override"))
						.addTextField("", ModelLocator.resourceManagerInstance.getString("calibrationservice","value"))
						.addOption(ModelLocator.resourceManagerInstance.getString("general","cancel"), DialogAction.STYLE_CANCEL, 1)
						.addOption("Ok", DialogAction.STYLE_POSITIVE, 0)
						.build()
					);
					alert.addEventListener(DialogViewEvent.CLOSED, bgValueOverride);
					alert.addEventListener(DialogViewEvent.CANCELLED, cancellation);
					
					DialogService.addDialog(alert);
					
					function cancellation(event:DialogViewEvent):void {
					}
					
					function bgValueOverride(event:DialogViewEvent):void {
						if (event.index == 1) {
							//it's a cancel
						} else {
							var asNumber:Number = new Number(event.values[0] as String);
							if (isNaN(asNumber)) {
								var alert:DialogView = Dialog.service.create(
									new AlertBuilder()
									.setTitle(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration_title"))
									.setMessage(ModelLocator.resourceManagerInstance.getString("calibrationservice","value_should_be_numeric"))
									.addOption("Ok", DialogAction.STYLE_POSITIVE, 0)
									.build()
								);
								DialogService.addDialog(alert);
								//and ask again a value
								calibrationOnRequest();
							} else {
								Calibration.clearLastCalibration();
								var newcalibration:Calibration = Calibration.create(asNumber).saveToDatabaseSynchronous();
								var calibrationServiceEvent:CalibrationServiceEvent = new CalibrationServiceEvent(CalibrationServiceEvent.NEW_CALIBRATION_EVENT);
								_instance.dispatchEvent(calibrationServiceEvent);
								myTrace("calibration override, new one = created : " + newcalibration.print("   "));
							}
						}
					}
				} else {
					var alert:DialogView = Dialog.service.create(
						new AlertBuilder()
						.setTitle(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration_title"))
						.setMessage(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_bg_value_without_override"))
						.addTextField("",ModelLocator.resourceManagerInstance.getString("calibrationservice","value"))
						.addOption(ModelLocator.resourceManagerInstance.getString("general","cancel"), DialogAction.STYLE_CANCEL, 1)
						.addOption("Ok", DialogAction.STYLE_POSITIVE, 0)
						.build()
					);
					alert.addEventListener(DialogViewEvent.CLOSED, bgValueWithoutOverride);
					alert.addEventListener(DialogViewEvent.CANCELLED, cancellation2);
					
					DialogService.addDialog(alert);
					
					function cancellation2(event:DialogViewEvent):void {
					}
					
					function bgValueWithoutOverride(event:DialogViewEvent):void {
						if (event.index == 1) {
							return;
						}
						var asNumber:Number = new Number(event.values[0] as String);
						if (isNaN(asNumber)) {
							var alert:DialogView = Dialog.service.create(
								new AlertBuilder()
								.setTitle(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration_title"))
								.setMessage(ModelLocator.resourceManagerInstance.getString("calibrationservice","value_should_be_numeric"))
								.addOption("Ok", DialogAction.STYLE_POSITIVE, 0)
								.build()
							);
							DialogService.addDialog(alert);
							//and ask again a value
							calibrationOnRequest();
						} else {
							var newcalibration:Calibration = Calibration.create(asNumber).saveToDatabaseSynchronous();
							_instance.dispatchEvent(new CalibrationServiceEvent(CalibrationServiceEvent.NEW_CALIBRATION_EVENT));
							myTrace("Calibration created : " + newcalibration.print("   "));
						}
					}
				}
			}
		}
		
		private static function calibrationValueEntered(event:DialogViewEvent):void {
			if (event.index == 1) {
				return;
			}
			var asNumber:Number = new Number(event.values[0] as String);
			if (isNaN(asNumber)) {
				//add the warning message
				var alert:DialogView = Dialog.service.create(
					new AlertBuilder()
					.setTitle(ModelLocator.resourceManagerInstance.getString("calibrationservice","enter_calibration_title"))
					.setMessage(ModelLocator.resourceManagerInstance.getString("calibrationservice","value_should_be_numeric"))
					.addOption("Ok", DialogAction.STYLE_POSITIVE, 0)
					.build()
				);
				DialogService.addDialog(alert);
				//and ask again a value
				initialCalibrate();
				Calibration.requestCalibrationIfRangeTooNarrow();
			} else {
				var calibration:Calibration = Calibration.create(asNumber).saveToDatabaseSynchronous();
				myTrace("Calibration created : " + calibration.print("   "));
			}
		}
		
		private static function myTrace(log:String):void {
			Trace.myTrace("xdrip-CalibrationService.as", log);
		}
	}
}