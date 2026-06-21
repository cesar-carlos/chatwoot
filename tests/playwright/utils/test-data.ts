import { faker } from '@faker-js/faker';

export const fake = {
  fullName: () => faker.person.fullName(),
  email: () => faker.internet.email().toLowerCase(),
  phoneNumber: () => faker.phone.number(),
  password: () => `Pw${faker.string.alphanumeric(10)}!`,
  inboxName: () => `E2E Inbox ${faker.string.alphanumeric(6)}`,
  evolutionInstanceName: (prefix = 'e2e') =>
    `${prefix}-${Date.now()}-${faker.string.alphanumeric(4).toLowerCase()}`,
};
