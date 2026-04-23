import { createUser, updateUser } from "./user_service";

export function bootstrapUser(name: string) {
  return createUser(name);
}

export function renameUser(id: string, name: string) {
  return updateUser(id, name);
}

export function buildUserCard(name: string) {
  const draft = createUser(name);
  return `${draft.name}:${draft.id}`;
}
