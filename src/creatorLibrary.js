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
