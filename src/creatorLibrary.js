export function libraryAccessLabel({ visibility } = {}) {
    return visibility === 'workspace' ? 'Delad' : 'Privat';
}

export function openPublicationLabel({ open_submission_state } = {}) {
    const labels = {
        review: 'Under granskning i Open',
        published: 'Publicerad i Open',
        changes_requested: 'Ändringar begärda i Open',
        rejected: 'Avslagen i Open'
    };
    return labels[open_submission_state] || null;
}

export function libraryPromptActionUrl(action, promptId) {
    if (!promptId || action !== 'use') return null;
    return `promptbanken.html?libraryItem=${encodeURIComponent(promptId)}`;
}

export function libraryPromptActions(promptId) {
    return {
        use: libraryPromptActionUrl('use', promptId),
        edit: true,
        add_to_package: true,
        share: true,
        submit_open: true
    };
}

export async function registerAndSelectLibraryItem({ items, requestedId, register, select }) {
    await register(items);
    if (!requestedId || !items.some((item) => item.id === requestedId)) return false;
    select(requestedId, { reveal: true });
    return true;
}
