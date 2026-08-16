import test from 'node:test';
import assert from 'node:assert/strict';
import { creatorUrl, isProfileIndexable, initialsFrom, safeExternalUrl } from './creator-page-lib.mjs';

test('creatorUrl bygger rätt sökväg', () => {
    assert.equal(creatorUrl('anna-andersson'), '/creator/anna-andersson/');
});

test('isProfileIndexable kräver namn och kort presentation', () => {
    assert.equal(isProfileIndexable({ display_name: 'Anna', bio_short: 'Konsult' }), true);
    assert.equal(isProfileIndexable({ display_name: 'Anna', bio_short: '' }), false);
    assert.equal(isProfileIndexable({ display_name: 'Anna', bio_short: '   ' }), false);
    assert.equal(isProfileIndexable({ display_name: '', bio_short: 'Konsult' }), false);
    assert.equal(isProfileIndexable({}), false);
});

test('initialsFrom ger max två versaler', () => {
    assert.equal(initialsFrom('Anna Andersson'), 'AA');
    assert.equal(initialsFrom('anna'), 'A');
    assert.equal(initialsFrom('Anna Maria Andersson'), 'AA');
    assert.equal(initialsFrom('Åsa Öberg'), 'ÅÖ');
    assert.equal(initialsFrom(''), '');
    assert.equal(initialsFrom(null), '');
});

test('safeExternalUrl släpper bara igenom http och https', () => {
    assert.equal(safeExternalUrl('https://example.com'), 'https://example.com');
    assert.equal(safeExternalUrl('http://example.com/x?y=1'), 'http://example.com/x?y=1');
    assert.equal(safeExternalUrl('javascript:alert(1)'), null);
    assert.equal(safeExternalUrl('data:text/html,x'), null);
    assert.equal(safeExternalUrl('//evil.com'), null);
    assert.equal(safeExternalUrl('/relativ'), null);
    assert.equal(safeExternalUrl(''), null);
    assert.equal(safeExternalUrl(null), null);
    assert.equal(safeExternalUrl(undefined), null);
});
