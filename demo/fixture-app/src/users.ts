import { createUser, findUser } from "./user_service";

export function openUsersPage() {
  const current = findUser("demo");
  return createUser(current.name);
}
