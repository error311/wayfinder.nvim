import { createUser, findUser } from "./user_service";

export function ensureDirectoryUser(id: string, fallback: string) {
  const current = findUser(id);
  return current.name ? current : createUser(fallback);
}
