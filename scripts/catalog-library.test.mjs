import test from 'node:test';
import assert from 'node:assert/strict';
import { catalogLibraryActionState } from '../src/catalogLibrary.js';

test('Open-innehåll som saknas får en aktiv Lägg till-handling', () => {
    assert.deepEqual(catalogLibraryActionState(false), {
        label: 'Lägg till i Mitt bibliotek',
        disabled: false,
        added: false
    });
});

test('en kanonisk Open-referens som redan finns blir inte möjlig att lägga till igen', () => {
    assert.deepEqual(catalogLibraryActionState(true), {
        label: '✓ Finns i Mitt bibliotek',
        disabled: true,
        added: true
    });
});
