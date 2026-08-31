export function catalogLibraryActionState(inLibrary) {
    return inLibrary
        ? { label: '✓ Finns i Mitt bibliotek', disabled: true, added: true }
        : { label: 'Lägg till i Mitt bibliotek', disabled: false, added: false };
}
