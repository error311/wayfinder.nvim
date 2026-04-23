export function createUser(name: string) {
  return {
    id: name.toLowerCase(),
    name,
  };
}

export function findUser(id: string) {
  return {
    id,
    name: "Demo User",
  };
}

export function updateUser(id: string, name: string) {
  return { id, name };
}

export function mergeUserDisplayName(id: string, fallback: string) {
  const current = findUser(id);
  return current.name || createUser(fallback).name;
}
