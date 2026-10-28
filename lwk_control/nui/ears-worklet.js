// Batches 128-sample render quanta into ~25 ms chunks (at 16 kHz) and posts them to the main thread.
class EarsCapture extends AudioWorkletProcessor {
    constructor() {
        super();
        this.buf = new Float32Array(400);
        this.len = 0;
    }

    process(inputs) {
        const ch = inputs[0] && inputs[0][0];
        if (!ch) return true;
        for (let i = 0; i < ch.length; i++) {
            this.buf[this.len++] = ch[i];
            if (this.len === this.buf.length) {
                this.port.postMessage(this.buf, [this.buf.buffer]);
                this.buf = new Float32Array(400);
                this.len = 0;
            }
        }
        return true;
    }
}

registerProcessor('ears-capture', EarsCapture);
