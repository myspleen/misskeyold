export class AddPgroongaIndexes1691850149834 {
    name = 'AddPgroongaIndexes1691850149834'
    async up(queryRunner) {
        await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS pgroonga;`);
        await queryRunner.query(`CREATE INDEX idx_note_text_cw_pgroonga ON note USING pgroonga(text, cw);`);
    }
    async down(queryRunner) {
        await queryRunner.query(`DROP INDEX idx_note_text_cw_pgroonga;`);
    }
}
