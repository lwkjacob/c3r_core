// Link tokens for the browser pop-out. Lua's math.random isn't made for secrets; Node's crypto is.
const crypto = require('crypto');
exports('newToken', () => crypto.randomBytes(24).toString('hex'));
