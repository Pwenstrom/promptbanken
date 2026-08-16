// Rena hjälpfunktioner för statiska creator-profilsidor.
// Se docs/superpowers/specs/2026-08-16-creator-profiler-design.md.

export function creatorUrl(slug) {
    return `/creator/${slug}/`;
}

function hasText(value) {
    return typeof value === 'string' && value.trim() !== '';
}

// Samma princip som paketens tröskel: en profil med bara ett namn är inget
// att skicka till en sökmotor.
export function isProfileIndexable(profile) {
    return hasText(profile?.display_name) && hasText(profile?.bio_short);
}

export function initialsFrom(displayName) {
    if (!hasText(displayName)) return '';
    const parts = displayName.trim().split(/\s+/);
    if (parts.length === 1) {
        return parts[0].charAt(0).toUpperCase();
    }
    return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
}

// Bara http/https får renderas. Utan den här spärren kan en
// självbetjäningsprofil injicera javascript:- eller data:-länkar, och
// protokollrelativa adresser (//evil.com) blir tysta utgångar från domänen.
export function safeExternalUrl(value) {
    if (typeof value !== 'string' || value.trim() === '') return null;
    const trimmed = value.trim();
    if (!/^https?:\/\//i.test(trimmed)) return null;
    return trimmed;
}
