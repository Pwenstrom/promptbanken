import test from 'node:test';
import assert from 'node:assert/strict';
import {
    libraryAccessLabel,
    libraryPromptActions,
    libraryPromptActionUrl,
    openPublicationLabel,
    registerAndSelectLibraryItem
} from '../src/creatorLibrary.js';

test('ett privat original kan vara publicerat i Open', () => {
    assert.equal(libraryAccessLabel({ visibility: 'private' }), 'Privat');
    assert.equal(openPublicationLabel({ open_submission_state: 'published' }), 'Publicerad i Open');
});

test('delat innehåll och väntande Open-inskick har separata etiketter', () => {
    assert.equal(libraryAccessLabel({ visibility: 'workspace' }), 'Delad');
    assert.equal(openPublicationLabel({ open_submission_state: 'review' }), 'Under granskning i Open');
});

test('utan inskick visas ingen Open-status', () => {
    assert.equal(openPublicationLabel({ open_submission_state: null }), null);
});

test('Använd är oberoende av Open-publicering', () => {
    const actions = libraryPromptActions('prompt-123');
    assert.equal(actions.use, 'promptbanken.html?libraryItem=prompt-123');
    assert.equal(actions.submit_open, true);
});

test('okända handlingar skapar ingen lokal URL', () => {
    assert.equal(libraryPromptActionUrl('delete', 'prompt-123'), null);
});

test('Använd väntar in registreringen och öppnar exakt den privata prompten', async () => {
    const events = [];
    const items = [{ id: 'prompt-123', title: 'Min prompt' }];

    const selected = await registerAndSelectLibraryItem({
        items,
        requestedId: 'prompt-123',
        register: async (registeredItems) => {
            await Promise.resolve();
            events.push(`registered:${registeredItems[0].id}`);
        },
        select: (id, options) => events.push(`selected:${id}:${options.reveal}`)
    });

    assert.equal(selected, true);
    assert.deepEqual(events, ['registered:prompt-123', 'selected:prompt-123:true']);
});

test('Använd väljer inte ett annat objekt när länken är inaktuell', async () => {
    const selectedIds = [];
    const selected = await registerAndSelectLibraryItem({
        items: [{ id: 'prompt-123' }],
        requestedId: 'saknas',
        register: async () => {},
        select: (id) => selectedIds.push(id)
    });

    assert.equal(selected, false);
    assert.deepEqual(selectedIds, []);
});
