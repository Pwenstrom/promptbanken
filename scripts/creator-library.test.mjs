import test from 'node:test';
import assert from 'node:assert/strict';
import {
    libraryAccessLabel,
    libraryPromptActions,
    libraryPromptActionUrl,
    openPublicationLabel
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
