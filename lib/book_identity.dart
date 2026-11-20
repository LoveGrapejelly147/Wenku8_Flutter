/// Local originals and virtual series share a reserved identity range.
const localBookIdStart = 0x60000000;
bool isLocalBook(int id) => id >= localBookIdStart;

/// Custom Legado-style sources use the range below local books and above
/// ordinary Wenku8 catalogue ids, so shelf, progress and cache keys stay stable.
const customSourceBookIdStart = 0x40000000;
bool isCustomSourceBook(int id) =>
    id >= customSourceBookIdStart && id < localBookIdStart;
