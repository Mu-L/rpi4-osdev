import bleno from 'bleno-mac';
import { uIOhook } from 'uiohook-napi';

const BlenoCharacteristic = bleno.Characteristic;

class EchoCharacteristic extends BlenoCharacteristic {
  constructor() {
    super({
      uuid: 'ec0e',
      properties: ['read', 'write', 'notify'],
      value: null
    });

    this._value = Buffer.alloc(0); 
    this._updateValueCallback = null;

    // Allocate tracking buffers internally
    this.buf = Buffer.allocUnsafe(4);
    this.obuf = Buffer.allocUnsafe(4);
    this.buttbuf = Buffer.allocUnsafe(2);

    // Screen layout matching properties
    this.scrwidth = 1440;
    this.scrheight = 900;
    this.divisorx = this.scrwidth / 320;
    this.divisory = this.scrheight / 200;

    // Start listening for mouse events natively inside the class
    this._setupMouseHooks();
  }

  _setupMouseHooks() {
    // 1. Mouse Movement
    uIOhook.on('mousemove', event => {
       this.buf.writeUInt16LE(Math.round(event.x / this.divisorx), 0);
       this.buf.writeUInt16LE(Math.round(event.y / this.divisory), 2);

       if (Buffer.compare(this.buf, this.obuf)) {
          this._value = this.buf;
          
          // CRITICAL: This is what actually transmits data over the air!
          if (this._updateValueCallback) {
             this._updateValueCallback(this._value);
          }
          this.buf.copy(this.obuf);
       }
    });

    // 2. Mouse Down
    uIOhook.on('mousedown', event => {
       this.buttbuf.writeUInt8(1, 0);
       this.buttbuf.writeUInt8(event.button, 1);

       this._value = this.buttbuf;
       if (this._updateValueCallback) {
          this._updateValueCallback(this._value);
       }
    });

    // 3. Mouse Up
    uIOhook.on('mouseup', event => {
       this.buttbuf.writeUInt8(2, 0);
       this.buttbuf.writeUInt8(event.button, 1);

       this._value = this.buttbuf;
       if (this._updateValueCallback) {
          this._updateValueCallback(this._value);
       }
    });

    // Fire up the hardware listener hook
    uIOhook.start();
  }

  onReadRequest(offset, callback) {
    console.log('EchoCharacteristic - onReadRequest: value = ' + this._value.toString('hex'));
    // Using bleno.Characteristic explicitly avoiding proto issues
    callback(bleno.Characteristic.RESULT_SUCCESS, this._value);
  }

  onWriteRequest(data, offset, withoutResponse, callback) {
    this._value = data;
    console.log('EchoCharacteristic - onWriteRequest: value = ' + this._value.toString('hex'));

    if (this._updateValueCallback) {
      console.log('EchoCharacteristic - onWriteRequest: notifying');
      this._updateValueCallback(this._value);
    }

    callback(bleno.Characteristic.RESULT_SUCCESS);
  }

  onSubscribe(maxValueSize, updateValueCallback) {
    console.log('EchoCharacteristic - onSubscribe: Central device has connected!');
    this._updateValueCallback = updateValueCallback;
  }

  onUnsubscribe() {
    console.log('EchoCharacteristic - onUnsubscribe');
    this._updateValueCallback = null;
  }
}

export default EchoCharacteristic;
