// 這個資源的規則住在這裡，這是整份 recipe 的重點。
// 兩支端點跟送給瀏覽器的那張表單，三個地方都來問這一份，所以它們走不散。
export const QUANTITY_MIN = 1;
export const QUANTITY_MAX = 10;

export function checkQuantity(value) {
  if (!Number.isInteger(value)) return "quantity must be an integer";
  if (value < QUANTITY_MIN || value > QUANTITY_MAX) {
    return `quantity must be between ${QUANTITY_MIN} and ${QUANTITY_MAX}`;
  }
  return null;
}
