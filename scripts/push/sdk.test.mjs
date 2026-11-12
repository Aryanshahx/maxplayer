import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

test('official Admin SDK modules and Firestore dependency load without credentials', () => {
  for (const value of [initializeApp, getFirestore, getMessaging, FieldValue.serverTimestamp]) assert.equal(typeof value, 'function');
});
