import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/build_proxy.tact',
    options: {
        debug: true,
    },
};
