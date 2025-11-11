import sql from './db/client.js';
import { ensureUser } from './controllers/user_controllers.js';

// Simular request/response
const mockReq = {
  body: {
    firebaseUid: 'test-uid-12345',
    email: 'test@example.com',
    displayName: 'Usuario Prueba',
    photoUrl: null
  }
};

const mockRes = {
  status: function(code) {
    this.statusCode = code;
    return this;
  },
  json: function(data) {
    console.log(`\n✅ Respuesta (${this.statusCode || 200}):`, JSON.stringify(data, null, 2));
    process.exit(0);
  }
};

console.log('🧪 Probando ensureUser...\n');
console.log('Body:', mockReq.body);

ensureUser(mockReq, mockRes).catch(err => {
  console.error('❌ Error:', err);
  process.exit(1);
});
